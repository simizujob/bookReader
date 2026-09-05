import XCTest
@testable import BookReader

final class MetadataBackfillServiceTests: XCTestCase {
    func test_backfillsAllPendingBooksAndMarksMetadataFetched() async throws {
        let repository = MockBookRepository()
        try repository.insert(BookDraft(
            isbn: "9784041031400",
            title: "ISBN: 9784041031400",
            seriesName: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: false
        ))

        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9784041031400"] = BookMetadata(
            title: "鬼滅の刃 19",
            coverImageURL: "https://example.com/cover.jpg"
        )

        let service = MetadataBackfillService(
            bookRepository: repository,
            metadataService: openLibrary,
            interRequestDelayNanoseconds: 0
        )
        await service.backfillPendingMetadata()

        let updated = try repository.find(isbn: "9784041031400")
        XCTAssertEqual(updated?.title, "鬼滅の刃 19")
        XCTAssertEqual(updated?.seriesName, "鬼滅の刃")
        XCTAssertEqual(updated?.volumeNumber, 19)
        XCTAssertEqual(updated?.metadataFetched, true)
        XCTAssertTrue(try repository.fetchPendingMetadata().isEmpty)
    }

    func test_openLibraryFailure_leavesBookPending() async throws {
        let repository = MockBookRepository()
        try repository.insert(BookDraft(
            isbn: "9789999999999",
            title: "ISBN: 9789999999999",
            seriesName: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: false
        ))

        let service = MetadataBackfillService(
            bookRepository: repository,
            metadataService: MockOpenLibraryService(),
            interRequestDelayNanoseconds: 0
        )
        await service.backfillPendingMetadata()

        XCTAssertEqual(try repository.fetchPendingMetadata().count, 1)
    }

    func test_noPendingBooks_doesNotCallOpenLibrary() async throws {
        let repository = MockBookRepository()
        try repository.insert(BookDraft(
            isbn: "9784041031400",
            title: "既に取得済み",
            seriesName: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))
        let openLibrary = MockOpenLibraryService()

        let service = MetadataBackfillService(bookRepository: repository, metadataService: openLibrary, interRequestDelayNanoseconds: 0)
        await service.backfillPendingMetadata()

        XCTAssertTrue(openLibrary.fetchedISBNs.isEmpty)
    }
}
