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

    private final class StubVolumeCountRefreshService: SeriesVolumeCountRefreshing {
        private(set) var refreshStaleSeriesCallCount = 0
        private(set) var refreshAllSeriesCallCount = 0
        private(set) var manualVolumeCounts: [(seriesKey: String, seriesName: String, total: Int)] = []
        private(set) var clearedCacheSeriesKeys: [String] = []
        func refreshStaleSeries() async { refreshStaleSeriesCallCount += 1 }
        func refreshAllSeries() async { refreshAllSeriesCallCount += 1 }
        func setManualVolumeCount(seriesKey: String, seriesName: String, total: Int) async {
            manualVolumeCounts.append((seriesKey, seriesName, total))
        }
        func clearVolumeCountCache(seriesKey: String) {
            clearedCacheSeriesKeys.append(seriesKey)
        }
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

    /// 回帰テスト: 本棚画面を開くたびに、再チェックが必要なシリーズ（既刊数「不明」等）だけを
    /// バックグラウンドで静かに再取得すること。1冊ずつ登録していく使い方では、残りの巻を
    /// 登録し終えた後にユーザーが手動でpull-to-refreshしなくても本棚を開くだけで
    /// 自動的に回復するようにするための対応。
    func test_onAppear_alsoRefreshesStaleSeriesInBackground() async {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        let refreshService = StubVolumeCountRefreshService()

        let viewModel = ShelfViewModel(
            bookRepository: repository,
            calculator: calculator,
            volumeCountRefreshService: refreshService
        )
        viewModel.onAppear()
        await viewModel.staleSeriesRefreshTask?.value

        XCTAssertEqual(refreshService.refreshStaleSeriesCallCount, 1)
        XCTAssertEqual(refreshService.refreshAllSeriesCallCount, 0, "onAppearでは全件ではなく再チェックが必要なものだけを対象とすること")
    }

    /// 本棚画面のpull-to-refresh用。キャッシュの鮮度に関わらず全シリーズを再取得し、
    /// 結果を画面に反映するためreload()も呼ばれること。
    func test_refreshSeriesVolumeCounts_forcesFullRefreshAndReloads() async {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        calculator.standalone = [makeBook()]
        let refreshService = StubVolumeCountRefreshService()

        let viewModel = ShelfViewModel(
            bookRepository: repository,
            calculator: calculator,
            volumeCountRefreshService: refreshService
        )
        await viewModel.refreshSeriesVolumeCounts()

        XCTAssertEqual(refreshService.refreshAllSeriesCallCount, 1)
        XCTAssertEqual(viewModel.standaloneBooks.count, 1, "再取得後に最新のデータへreloadされること")
    }

    /// シリーズの「削除」操作で、そのシリーズに属する全ての巻がまとめて削除され、
    /// 画面が最新の状態にreloadされること。
    func test_deleteSeries_removesAllVolumesAndReloads() {
        let repository = MockBookRepository()
        let seriesKey = SeriesKeyNormalizer.normalize("三体")
        repository.seed(Book(
            id: UUID(), isbn: nil, title: "三体 1", seriesName: "三体", seriesKey: seriesKey,
            volumeNumber: 1, coverImageURL: nil, status: .owned, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        ))
        repository.seed(Book(
            id: UUID(), isbn: nil, title: "三体 2", seriesName: "三体", seriesKey: seriesKey,
            volumeNumber: 2, coverImageURL: nil, status: .owned, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        ))
        let calculator = StubCalculator()
        let series = SeriesProgress(
            seriesKey: seriesKey, seriesName: "三体", ownedVolumes: [1, 2],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: nil, nextVolumeISBN: nil, volumes: []
        )
        let refreshService = StubVolumeCountRefreshService()

        let viewModel = ShelfViewModel(
            bookRepository: repository,
            calculator: calculator,
            volumeCountRefreshService: refreshService
        )
        viewModel.deleteSeries(series)

        XCTAssertTrue(repository.books.isEmpty, "シリーズに属する全ての巻が削除されること")
        XCTAssertEqual(
            refreshService.clearedCacheSeriesKeys, [seriesKey],
            "既刊総数のキャッシュも合わせて破棄し、再スキャン時に既刊数の再取得が走るようにすること"
        )
    }

    func test_openStoreSearchForBook_usesISBNWhenAvailable() {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)

        let url = viewModel.openStoreSearch(for: makeBook(isbn: "9781111111111"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "k" }?.value, "9781111111111")
    }

    // MARK: - displayedItems（本とシリーズを混同した一覧・検索・ソート）

    /// 回帰テスト: 「本」セクションと「シリーズ」セクションを分けず、1つのリストとして
    /// 混同表示すること。
    func test_displayedItems_mixesStandaloneBooksAndSeries() {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        calculator.standalone = [makeBook()]
        calculator.series = [SeriesProgress(
            seriesKey: "sanhti", seriesName: "三体", ownedVolumes: [1],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: 2, nextVolumeISBN: nil, volumes: []
        )]

        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)
        viewModel.onAppear()

        XCTAssertEqual(viewModel.displayedItems.count, 2)
    }

    func test_displayedItems_filtersBySearchText() {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        calculator.standalone = [makeBook()] // title: "三体"
        calculator.series = [SeriesProgress(
            seriesKey: "onepiece", seriesName: "ONE PIECE", ownedVolumes: [1],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: 2, nextVolumeISBN: nil, volumes: []
        )]

        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)
        viewModel.onAppear()
        viewModel.searchText = "ONE"

        XCTAssertEqual(viewModel.displayedItems.map(\.sortTitle), ["ONE PIECE"])
    }

    func test_displayedItems_defaultsToNewestFirst() {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        calculator.standalone = [
            makeBook(daysAgo: 5),
            makeBook(daysAgo: 0)
        ]

        let viewModel = ShelfViewModel(bookRepository: repository, calculator: calculator)
        XCTAssertEqual(viewModel.sortOption, .newest, "初期状態は登録が新しい順であること")
        viewModel.onAppear()

        XCTAssertEqual(viewModel.displayedItems.first?.latestRegisteredAt, calculator.standalone[1].registeredAt)
    }

    /// 回帰テスト: 既刊数不明のシリーズについてユーザーが手動で既刊総数を入力した場合、
    /// 既刊数が判明した場合と同じ経路（SeriesVolumeCountRefreshService）を通し、
    /// 完了後にreloadして画面へ反映すること。
    func test_setManualVolumeCount_delegatesToRefreshServiceAndReloads() async {
        let repository = MockBookRepository()
        let calculator = StubCalculator()
        let series = SeriesProgress(
            seriesKey: "sanhti", seriesName: "三体", ownedVolumes: [1],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: 2, nextVolumeISBN: nil, volumes: []
        )
        calculator.series = [series]
        let refreshService = StubVolumeCountRefreshService()

        let viewModel = ShelfViewModel(
            bookRepository: repository,
            calculator: calculator,
            volumeCountRefreshService: refreshService
        )
        viewModel.setManualVolumeCount(for: series, total: 5)
        await viewModel.manualVolumeCountTask?.value

        XCTAssertEqual(refreshService.manualVolumeCounts.count, 1)
        XCTAssertEqual(refreshService.manualVolumeCounts.first?.seriesKey, "sanhti")
        XCTAssertEqual(refreshService.manualVolumeCounts.first?.seriesName, "三体")
        XCTAssertEqual(refreshService.manualVolumeCounts.first?.total, 5)
    }
}
