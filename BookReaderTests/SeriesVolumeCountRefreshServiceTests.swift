import XCTest
@testable import BookReader

final class SeriesVolumeCountRefreshServiceTests: XCTestCase {
    private final class StubMetadataService: BookMetadataFetching {
        var volumeCountBySeriesName: [String: Int] = [:]
        private(set) var requestedSeriesNames: [String] = []

        func fetchMetadata(isbn: String) async throws -> BookMetadata {
            throw BookMetadataError.notFound
        }

        func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
            requestedSeriesNames.append(seriesName)
            return volumeCountBySeriesName[seriesName]
        }
    }

    private var persistence: PersistenceController!
    private var repository: CoreDataBookRepository!
    private var cache: CoreDataSeriesMetadataCache!
    private var calculator: SeriesProgressCalculator!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        repository = CoreDataBookRepository(context: context, notificationService: MockReminderScheduler())
        cache = CoreDataSeriesMetadataCache(context: context)
        calculator = SeriesProgressCalculator(bookRepository: repository, metadataCache: cache)
    }

    private func insertOwned(seriesName: String, volume: Int) throws {
        try repository.insert(BookDraft(
            isbn: nil,
            title: "\(seriesName) \(volume)",
            seriesName: seriesName,
            volumeNumber: volume,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))
    }

    func test_refreshStaleSeries_fetchesAndCachesVolumeCountForNewSeries() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        let metadataService = StubMetadataService()
        metadataService.volumeCountBySeriesName["三体"] = 3

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        let cached = try cache.cached(seriesKey: SeriesKeyNormalizer.normalize("三体"))
        XCTAssertEqual(cached?.knownTotalVolumes, 3)
        XCTAssertEqual(metadataService.requestedSeriesNames, ["三体"])
    }

    func test_refreshStaleSeries_alreadyFreshCache_doesNotRequestAgain() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        try cache.upsert(seriesKey: SeriesKeyNormalizer.normalize("三体"), totalVolumes: 3)

        let metadataService = StubMetadataService()
        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        XCTAssertTrue(metadataService.requestedSeriesNames.isEmpty, "直近に取得済みのキャッシュは再取得しないこと")
    }

    func test_refreshStaleSeries_metadataServiceReturnsNil_cachesAsUnknown() async throws {
        try insertOwned(seriesName: "ONE PIECE", volume: 1)
        let metadataService = StubMetadataService() // volumeCountBySeriesNameを設定しない = nilを返す

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        let cached = try cache.cached(seriesKey: SeriesKeyNormalizer.normalize("ONE PIECE"))
        XCTAssertNil(cached?.knownTotalVolumes)
        // lastFetchedAtは更新され、次回のむやみな再取得を防ぐこと
        XCTAssertNotNil(cached)
    }

    /// 既刊総数が判明したら、未登録の巻を「気になる本棚」（未購入）としてまとめて自動登録し、
    /// 本棚統合画面で全巻を一覧表示できるようにする（ユーザー要望対応）。
    func test_refreshStaleSeries_knownTotalVolumes_backfillsMissingVolumesAsWishlist() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        let metadataService = StubMetadataService()
        metadataService.volumeCountBySeriesName["三体"] = 3

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        let volumes = try XCTUnwrap(progress?.volumes)
        XCTAssertEqual(volumes.map(\.volumeNumber), [1, 2, 3])
        XCTAssertEqual(volumes.first { $0.volumeNumber == 1 }?.unifiedStatus, .unread)
        XCTAssertEqual(volumes.first { $0.volumeNumber == 2 }?.unifiedStatus, .wishlist)
        XCTAssertEqual(volumes.first { $0.volumeNumber == 3 }?.unifiedStatus, .wishlist)
    }

    func test_refreshStaleSeries_allVolumesAlreadyRegistered_doesNotDuplicate() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        try insertOwned(seriesName: "三体", volume: 2)
        let metadataService = StubMetadataService()
        metadataService.volumeCountBySeriesName["三体"] = 2

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        XCTAssertEqual(progress?.volumes.count, 2, "既に全巻登録済みの場合は重複登録しないこと")
    }

    func test_refreshStaleSeries_metadataServiceReturnsNil_doesNotBackfill() async throws {
        try insertOwned(seriesName: "ONE PIECE", volume: 1)
        let metadataService = StubMetadataService() // volumeCountBySeriesNameを設定しない = nilを返す

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        let progress = try calculator.calculateAll().first { $0.seriesName == "ONE PIECE" }
        XCTAssertEqual(progress?.volumes.count, 1, "既刊総数が不明な場合は自動登録しないこと")
    }

    func test_refreshStaleSeries_noOwnedBooks_doesNothing() async throws {
        let metadataService = StubMetadataService()
        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        XCTAssertTrue(metadataService.requestedSeriesNames.isEmpty)
    }
}
