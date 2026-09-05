import XCTest
@testable import BookReader

final class SeriesVolumeCountRefreshServiceTests: XCTestCase {
    private final class StubMetadataService: BookMetadataFetching {
        var volumeCountBySeriesName: [String: Int] = [:]
        var isbnsBySeriesName: [String: [Int: String]] = [:]
        private(set) var requestedSeriesNames: [String] = []

        func fetchMetadata(isbn: String) async throws -> BookMetadata {
            throw BookMetadataError.notFound
        }

        func fetchSeriesVolumeCount(seriesName: String) async throws -> SeriesVolumeCountResult? {
            requestedSeriesNames.append(seriesName)
            guard let total = volumeCountBySeriesName[seriesName] else { return nil }
            return SeriesVolumeCountResult(total: total, isbnsByVolume: isbnsBySeriesName[seriesName] ?? [:])
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

    /// 既刊数がNDL Searchから自動判明した場合、未登録の巻には実ISBNを登録し、Amazon購入リンクが
    /// キーワード検索ではなくISBN検索になるようにすること。
    func test_refreshStaleSeries_knownTotalVolumes_backfillsWithRealISBNsFromNDL() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        let metadataService = StubMetadataService()
        metadataService.volumeCountBySeriesName["三体"] = 3
        metadataService.isbnsBySeriesName["三体"] = [2: "9784000000002", 3: "9784000000003"]

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        let vol2 = try repository.find(seriesKey: SeriesKeyNormalizer.normalize("三体"), volumeNumber: 2)
        let vol3 = try repository.find(seriesKey: SeriesKeyNormalizer.normalize("三体"), volumeNumber: 3)
        XCTAssertEqual(vol2?.isbn, "9784000000002")
        XCTAssertEqual(vol3?.isbn, "9784000000003")
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

    /// 回帰テスト: 検索クエリに使うシリーズ名は、Book配列内でたまたま先頭に来た表記ではなく、
    /// SeriesProgressCalculatorが選ぶ「多数派の表記」と一致していること。
    /// 以前はbookRepository.fetchAll()の配列で先頭に来た本の表記をそのまま検索クエリに
    /// 使っていたため、ムック本など少数派の表記の本が先頭になると検索が空振りし、
    /// 既刊数が「不明」になる不具合があった。
    func test_refreshStaleSeries_usesMajorityVariantAsSearchQuery_notArbitraryFirstBook() async throws {
        // 少数派の表記ゆれ本（ムック本相当、巻数なし）を先に登録し、配列の先頭に来やすい状況を再現する
        try repository.insert(BookDraft(
            isbn: nil, title: "hunter×hunterファンブック", seriesName: "hunter×hunter",
            volumeNumber: nil, coverImageURL: nil, status: .owned, readStatus: .unread, metadataFetched: true
        ))
        try insertOwned(seriesName: "HUNTER×HUNTER", volume: 1)
        try insertOwned(seriesName: "HUNTER×HUNTER", volume: 2)
        try insertOwned(seriesName: "HUNTER×HUNTER", volume: 3)

        let metadataService = StubMetadataService()
        metadataService.volumeCountBySeriesName["HUNTER×HUNTER"] = 3

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        XCTAssertEqual(metadataService.requestedSeriesNames, ["HUNTER×HUNTER"], "検索クエリには多数派の表記が使われること")
    }

    /// 回帰テスト: 情報源（BookMetadataFetching実装）が誤って非現実的な既刊総数を返した場合に、
    /// キャッシュ保存や全巻自動登録を行わないこと。OpenLibraryServiceの旧実装が自由文字列検索の
    /// ヒット件数（数万件）をそのまま返してしまい、全巻自動登録が暴走しかけた不具合があったため、
    /// SeriesVolumeCountRefreshService側でも境界値検証として上限を設けている。
    func test_refreshStaleSeries_implausiblyLargeCount_isDiscardedAsUnknown() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        let metadataService = StubMetadataService()
        metadataService.volumeCountBySeriesName["三体"] = 57799

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )
        await service.refreshStaleSeries()

        let cached = try cache.cached(seriesKey: SeriesKeyNormalizer.normalize("三体"))
        XCTAssertNil(cached?.knownTotalVolumes, "非現実的に大きい値は既刊総数として採用しないこと")

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        XCTAssertEqual(progress?.volumes.count, 1, "非現実的に大きい値では全巻自動登録を行わないこと")
    }

    /// 回帰テスト: 既刊数取得ロジックの変更直後など、直近にキャッシュされた「不明」等の古い結果を
    /// 30日待たずにユーザーが手動で更新できるようにするための機能（本棚のpull-to-refresh用）。
    /// refreshStaleSeries()と異なり、キャッシュが新しくても常に再取得すること。
    func test_refreshAllSeries_refetchesEvenWhenCacheIsFresh() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        try cache.upsert(seriesKey: SeriesKeyNormalizer.normalize("三体"), totalVolumes: nil) // 直近キャッシュ済みの「不明」

        let metadataService = StubMetadataService()
        metadataService.volumeCountBySeriesName["三体"] = 3 // ロジック変更等で今なら取得できる想定
        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: metadataService,
            interRequestDelayNanoseconds: 0
        )

        await service.refreshAllSeries()

        XCTAssertEqual(metadataService.requestedSeriesNames, ["三体"], "キャッシュが新しくても再取得すること")
        let cached = try cache.cached(seriesKey: SeriesKeyNormalizer.normalize("三体"))
        XCTAssertEqual(cached?.knownTotalVolumes, 3)
    }

    // MARK: - clearVolumeCountCache（シリーズ削除後の再取得のため）

    /// 回帰テスト: シリーズを削除しても既刊総数のキャッシュを残したままだと、同じシリーズの
    /// 巻を再度スキャン登録した際に「キャッシュは新しいので再取得不要」と誤認識され、
    /// 全巻自動登録が二度と走らなくなる不具合があった。キャッシュも合わせて削除することで、
    /// 次回の再チェック対象に戻ることを確認する。
    func test_clearVolumeCountCache_removesEntryAndSeriesBecomesEligibleForRefreshAgain() async throws {
        let seriesKey = SeriesKeyNormalizer.normalize("三体")
        try cache.upsert(seriesKey: seriesKey, totalVolumes: 5) // 削除前に既刊数が判明していた状態を再現

        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: StubMetadataService(),
            interRequestDelayNanoseconds: 0
        )
        service.clearVolumeCountCache(seriesKey: seriesKey)

        XCTAssertNil(try cache.cached(seriesKey: seriesKey), "キャッシュが削除されていること")

        // シリーズを再スキャン登録した状況を再現し、再チェック対象に含まれることを確認する
        try insertOwned(seriesName: "三体", volume: 1)
        let staleKeys = try calculator.seriesKeysNeedingRefresh()
        XCTAssertTrue(staleKeys.contains(seriesKey), "キャッシュ削除後は再チェック対象に戻ること")
    }

    // MARK: - setManualVolumeCount（既刊数不明時のユーザー手動入力）

    func test_setManualVolumeCount_cachesValueAndBackfillsMissingVolumes() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: StubMetadataService(),
            interRequestDelayNanoseconds: 0
        )

        await service.setManualVolumeCount(seriesKey: SeriesKeyNormalizer.normalize("三体"), seriesName: "三体", total: 3)

        let cached = try cache.cached(seriesKey: SeriesKeyNormalizer.normalize("三体"))
        XCTAssertEqual(cached?.knownTotalVolumes, 3)
        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        XCTAssertEqual(progress?.volumes.map(\.volumeNumber), [1, 2, 3], "既刊数が判明した場合と同様に未登録の巻を自動登録すること")
        XCTAssertEqual(progress?.volumes.first { $0.volumeNumber == 2 }?.unifiedStatus, .wishlist)
    }

    /// 回帰テスト: 巻数を手動設定した場合はNDLの巻ごとのISBNデータが無いため、未登録の巻は
    /// ISBNなしのまま登録し、Amazon購入リンクはキーワード検索にフォールバックすること
    /// （実ISBN検索が使えるのは既刊数が自動判明した場合のみ）。
    func test_setManualVolumeCount_backfillsWithoutISBN() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: StubMetadataService(),
            interRequestDelayNanoseconds: 0
        )

        await service.setManualVolumeCount(seriesKey: SeriesKeyNormalizer.normalize("三体"), seriesName: "三体", total: 3)

        let vol2 = try repository.find(seriesKey: SeriesKeyNormalizer.normalize("三体"), volumeNumber: 2)
        XCTAssertNil(vol2?.isbn, "巻数を手動設定した場合はキーワード検索にフォールバックすること")
    }

    func test_setManualVolumeCount_implausiblyLargeValue_isIgnored() async throws {
        try insertOwned(seriesName: "三体", volume: 1)
        let service = SeriesVolumeCountRefreshService(
            bookRepository: repository,
            calculator: calculator,
            metadataCache: cache,
            metadataService: StubMetadataService(),
            interRequestDelayNanoseconds: 0
        )

        await service.setManualVolumeCount(seriesKey: SeriesKeyNormalizer.normalize("三体"), seriesName: "三体", total: 99999)

        let cached = try cache.cached(seriesKey: SeriesKeyNormalizer.normalize("三体"))
        XCTAssertNil(cached, "非現実的な値は採用しないこと")
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
