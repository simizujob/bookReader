import XCTest
@testable import BookReader

@MainActor
final class ShelfViewModelTests: XCTestCase {
    private final class StubCalculator: SeriesProgressCalculating {
        var series: [SeriesProgress] = []
        var standalone: [Book] = []
        func calculateAll() throws -> [SeriesProgress] { series }
        func standaloneBooks() throws -> [Book] { standalone }
        func seriesKeysNeedingRefresh() throws -> [String] { [] }
    }

    private func makeBook(
        status: OwnershipStatus = .wishlist,
        readStatus: ReadStatus = .unread,
        isbn: String? = "9789999999999",
        daysAgo: Int = 0
    ) -> Book {
        Book(
            id: UUID(), isbn: isbn, title: "三体", seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: status, readStatus: readStatus,
            registeredAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            lastOpenedAt: nil, metadataFetched: true
        )
    }

    func test_onAppear_populatesSeriesCardsAndStandaloneBooks() {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        calculator.standalone = [makeBook()]
        let progress = SeriesProgress(
            seriesKey: "sanhti", seriesName: "三体", ownedVolumes: [1],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: 2, nextVolumeISBN: nil, volumes: []
        )
        calculator.series = [progress]

        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)
        viewModel.onAppear()

        XCTAssertEqual(viewModel.standaloneBooks.count, 1)
        XCTAssertEqual(viewModel.seriesCards, [progress])
    }

    /// ステータス変更は2タップ（ピルのメニューから選択）で完了し、リロードまで行われること。
    func test_changeStatus_updatesBookAndReloads() {
        let repository = MockBookRepository()
        let book = makeBook(status: .wishlist, readStatus: .unread)
        repository.seed(book)
        let calculator = StubCalculator()

        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)
        viewModel.changeStatus(bookID: book.id, to: .reading)

        let updated = try? repository.find(id: book.id)
        XCTAssertEqual(updated?.status, .owned)
        XCTAssertEqual(updated?.readStatus, .reading)
    }

    func test_changeStatus_toWishlist_setsOwnershipBackToWishlist() {
        let repository = MockBookRepository()
        let book = makeBook(status: .owned, readStatus: .finished)
        repository.seed(book)
        let calculator = StubCalculator()

        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)
        viewModel.changeStatus(bookID: book.id, to: .wishlist)

        let updated = try? repository.find(id: book.id)
        XCTAssertEqual(updated?.status, .wishlist)
    }

    func test_isOverdue_trueAtOrBeyond30Days() {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)

        XCTAssertTrue(viewModel.isOverdue(makeBook(daysAgo: 30)))
        XCTAssertFalse(viewModel.isOverdue(makeBook(daysAgo: 29)))
    }

    func test_openStoreSearchForBook_usesISBNWhenAvailable() {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)

        let url = viewModel.openStoreSearch(for: makeBook(isbn: "9781111111111"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "k" }?.value, "9781111111111")
    }
}
