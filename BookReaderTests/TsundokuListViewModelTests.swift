import XCTest
@testable import BookReader

@MainActor
final class TsundokuListViewModelTests: XCTestCase {
    private func makeBook(daysAgo: Int, readStatus: ReadStatus = .unread, status: OwnershipStatus = .owned) -> Book {
        Book(
            id: UUID(),
            isbn: "9784041031400",
            title: "三体",
            seriesName: nil,
            seriesKey: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: status,
            readStatus: readStatus,
            registeredAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            lastOpenedAt: nil,
            metadataFetched: true
        )
    }

    func test_onAppear_loadsOnlyCurrentSegment() {
        let repository = MockBookRepository()
        repository.seed(makeBook(daysAgo: 1, readStatus: .unread))
        repository.seed(makeBook(daysAgo: 1, readStatus: .finished))

        let viewModel = TsundokuListViewModel(bookRepository: repository)
        viewModel.segment = .unread
        viewModel.onAppear()

        XCTAssertEqual(viewModel.books.count, 1)
    }

    func test_isOverdue_trueAtOrBeyond30Days() {
        let repository = MockBookRepository()
        let viewModel = TsundokuListViewModel(bookRepository: repository)

        XCTAssertTrue(viewModel.isOverdue(makeBook(daysAgo: 30)))
        XCTAssertTrue(viewModel.isOverdue(makeBook(daysAgo: 45)))
        XCTAssertFalse(viewModel.isOverdue(makeBook(daysAgo: 29)))
    }

    func test_markAsFinished_movesBookOutOfUnreadSegment() {
        let repository = MockBookRepository()
        let book = makeBook(daysAgo: 5, readStatus: .unread)
        repository.seed(book)

        let viewModel = TsundokuListViewModel(bookRepository: repository)
        viewModel.segment = .unread
        viewModel.onAppear()
        XCTAssertEqual(viewModel.books.count, 1)

        viewModel.markAsFinished(book)
        XCTAssertEqual(viewModel.books.count, 0)

        viewModel.segment = .finished
        viewModel.reload()
        XCTAssertEqual(viewModel.books.count, 1)
    }
}
