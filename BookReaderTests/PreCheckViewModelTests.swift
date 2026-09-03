import XCTest
@testable import BookReader

@MainActor
final class PreCheckViewModelTests: XCTestCase {
    func test_judge_ownedISBN_setsJudgedOwned() {
        let repository = MockBookRepository()
        repository.seed(Book(
            id: UUID(), isbn: "9784041031400", title: "三体", seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: .owned, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        ))
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9784041031400")

        XCTAssertEqual(viewModel.scanState, .judged(.owned))
    }

    func test_judge_unknownISBN_immediatelyNotOwnedWithoutEnrichment() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")

        XCTAssertEqual(viewModel.scanState, .judged(.notOwned(possibleEdition: nil)))
        // バーコード単独ではタイトルが未知のため、この時点ではeditionWarning等は設定されない
        XCTAssertNil(viewModel.enrichedContext.editionWarning)
    }

    func test_judge_unknownISBN_afterMetadataResolves_detectsEditionWarning() async throws {
        let repository = MockBookRepository()
        // 単行本を所持している状態で、文庫版（別ISBN）をスキャンするケース
        try repository.insert(BookDraft(
            isbn: "9781111111111",
            title: "三体",
            seriesName: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))

        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9782222222222"] = OpenLibraryBookMetadata(title: "三体", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: openLibrary)
        viewModel.judge(isbn: "9782222222222")
        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.enrichedContext.editionWarning?.matchedBook.isbn, "9781111111111")
    }

    func test_judge_unknownISBN_afterMetadataResolves_detectsPartialSeriesOwnership() async throws {
        let repository = MockBookRepository()
        try repository.insert(BookDraft(
            isbn: "9781111111111",
            title: "鬼滅の刃 19",
            seriesName: "鬼滅の刃",
            volumeNumber: 19,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))

        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9782222222222"] = OpenLibraryBookMetadata(title: "鬼滅の刃 20", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: openLibrary)
        viewModel.judge(isbn: "9782222222222")
        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.enrichedContext.partialSeriesInfo?.ownedThrough, 19)
        XCTAssertEqual(viewModel.enrichedContext.partialSeriesInfo?.missingVolume, 20)
    }

    func test_addCurrentResultToWishlist_registersAsWishlist() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        viewModel.addCurrentResultToWishlist()

        XCTAssertEqual(repository.insertedDrafts.count, 1)
        XCTAssertEqual(repository.insertedDrafts.first?.status, .wishlist)
        XCTAssertEqual(repository.insertedDrafts.first?.isbn, "9789999999999")
    }
}
