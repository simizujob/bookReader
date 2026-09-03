import XCTest
@testable import BookReader

@MainActor
final class BookDetailViewModelTests: XCTestCase {
    private func makeBook() -> Book {
        Book(
            id: UUID(), isbn: "9784041031400", title: "三体", seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: .owned, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
    }

    func test_save_persistsEditedFields() throws {
        let repository = MockBookRepository()
        let book = makeBook()
        repository.seed(book)

        let viewModel = BookDetailViewModel(book: book, bookRepository: repository)
        viewModel.editableTitle = "三体 (改題)"
        viewModel.editableSeriesName = "三体シリーズ"
        viewModel.editableVolumeNumber = 1
        XCTAssertTrue(viewModel.save())

        let updated = try repository.find(id: book.id)
        XCTAssertEqual(updated?.title, "三体 (改題)")
        XCTAssertEqual(updated?.seriesName, "三体シリーズ")
        XCTAssertEqual(updated?.volumeNumber, 1)
    }

    func test_delete_removesBookAndSetsDidDelete() throws {
        let repository = MockBookRepository()
        let book = makeBook()
        repository.seed(book)

        let viewModel = BookDetailViewModel(book: book, bookRepository: repository)
        viewModel.delete()

        XCTAssertTrue(viewModel.didDelete)
        XCTAssertNil(try repository.find(id: book.id))
    }
}
