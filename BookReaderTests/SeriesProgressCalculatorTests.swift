import XCTest
@testable import BookReader

final class SeriesProgressCalculatorTests: XCTestCase {
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

    @discardableResult
    private func insertOwned(seriesName: String, volume: Int, isbn: String? = nil) throws -> Book {
        try repository.insert(BookDraft(
            isbn: isbn,
            title: "\(seriesName) \(volume)",
            seriesName: seriesName,
            volumeNumber: volume,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))
    }

    func test_knownTotalVolumes_calculatesCompletionRateAndMissingVolumes() throws {
        try insertOwned(seriesName: "三体", volume: 1)
        try insertOwned(seriesName: "三体", volume: 2)
        try cache.upsert(seriesKey: SeriesKeyNormalizer.normalize("三体"), totalVolumes: 3)

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        XCTAssertEqual(progress?.ownedVolumes, [1, 2])
        XCTAssertEqual(progress?.missingVolumes, [3])
        let completionRate = try XCTUnwrap(progress?.completionRate)
        XCTAssertEqual(completionRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(progress?.nextVolumeToBuy, 3)
    }

    func test_unknownTotalVolumes_fallsBackToOwnedMaxPlusOne() throws {
        try insertOwned(seriesName: "チェンソーマン", volume: 1)
        try insertOwned(seriesName: "チェンソーマン", volume: 17)
        // 既刊総数キャッシュは未登録のまま

        let progress = try calculator.calculateAll().first { $0.seriesName == "チェンソーマン" }
        XCTAssertNil(progress?.missingVolumes)
        XCTAssertNil(progress?.completionRate)
        XCTAssertEqual(progress?.nextVolumeToBuy, 18)
    }

    /// 回帰テスト: シリーズ名が未確定の「気になるリストへ」登録本(seriesKey == nil)が
    /// calculateAll()から漏れても、standaloneBooks()で拾えること。
    func test_standaloneBooks_includesWishlistBooksWithoutSeriesKey() throws {
        try repository.insert(BookDraft(
            isbn: "9789999999999",
            title: "ISBN: 9789999999999",
            seriesName: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .wishlist,
            readStatus: .unread,
            metadataFetched: false
        ))

        let standalone = try calculator.standaloneBooks()
        XCTAssertEqual(standalone.count, 1)
        XCTAssertEqual(standalone.first?.isbn, "9789999999999")

        // calculateAll()のシリーズカードには出てこないことも確認する（表示漏れの再発防止）
        XCTAssertTrue(try calculator.calculateAll().isEmpty)
    }

    /// 本棚統合画面では所持済みの単発本（旧・積読リスト相当）もstandaloneBooksに含める。
    func test_standaloneBooks_includesOwnedBooksWithoutSeriesKey() throws {
        try repository.insert(BookDraft(
            isbn: "9789999999999",
            title: "所持済みの単発本",
            seriesName: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))

        let standalone = try calculator.standaloneBooks()
        XCTAssertEqual(standalone.count, 1)
        XCTAssertEqual(standalone.first?.isbn, "9789999999999")
    }

    func test_standaloneBooks_excludesSeriesBooks() throws {
        try insertOwned(seriesName: "三体", volume: 1) // seriesKeyあり
        XCTAssertTrue(try calculator.standaloneBooks().isEmpty)
    }

    func test_nextVolumeISBN_resolvedWhenWishlistBookExists() throws {
        try insertOwned(seriesName: "鬼滅の刃", volume: 1)
        try repository.insert(BookDraft(
            isbn: "9784041031400",
            title: "鬼滅の刃 2",
            seriesName: "鬼滅の刃",
            volumeNumber: 2,
            coverImageURL: nil,
            status: .wishlist,
            readStatus: .unread,
            metadataFetched: true
        ))

        let progress = try calculator.calculateAll().first { $0.seriesName == "鬼滅の刃" }
        XCTAssertEqual(progress?.nextVolumeToBuy, 2)
        XCTAssertEqual(progress?.nextVolumeISBN, "9784041031400")
    }

    func test_nextVolumeISBN_nilWhenNoMatchingWishlistBook() throws {
        try insertOwned(seriesName: "進撃の巨人", volume: 1)

        let progress = try calculator.calculateAll().first { $0.seriesName == "進撃の巨人" }
        XCTAssertEqual(progress?.nextVolumeToBuy, 2)
        XCTAssertNil(progress?.nextVolumeISBN)
    }

    func test_isNearCompletion_trueWhenOneVolumeRemaining() throws {
        try insertOwned(seriesName: "三体", volume: 1)
        try insertOwned(seriesName: "三体", volume: 2)
        try cache.upsert(seriesKey: SeriesKeyNormalizer.normalize("三体"), totalVolumes: 3)

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        XCTAssertEqual(progress?.isNearCompletion, true)
    }

    // MARK: - 本棚統合（volumes / statusCounts）

    func test_volumes_includesOwnedAndWishlistWithUnifiedStatus() throws {
        try insertOwned(seriesName: "鬼滅の刃", volume: 1)
        let inserted = try repository.insert(BookDraft(
            isbn: nil, title: "鬼滅の刃 2", seriesName: "鬼滅の刃", volumeNumber: 2,
            coverImageURL: nil, status: .wishlist, readStatus: .unread, metadataFetched: true
        ))

        let progress = try calculator.calculateAll().first { $0.seriesName == "鬼滅の刃" }
        let volumes = try XCTUnwrap(progress?.volumes)
        XCTAssertEqual(volumes.map(\.volumeNumber), [1, 2])
        XCTAssertEqual(volumes.first?.unifiedStatus, .unread)
        XCTAssertEqual(
            volumes.last,
            SeriesVolumeEntry(
                bookID: inserted.id, volumeNumber: 2, unifiedStatus: .wishlist,
                registeredAt: inserted.registeredAt, displayLabel: "2巻"
            )
        )
    }

    // MARK: - 代表シリーズ名の決定性（既刊数「不明」フリップフロップの回帰テスト）

    /// 回帰テスト: グループ内に少数派の表記ゆれ（大文字小文字・全角半角違い）が混ざっていると、
    /// Dictionary(grouping:)の要素順が不定なため単純にfirst(where:)で代表シリーズ名を選ぶと
    /// 実行（アプリの再起動）ごとに異なる表記が選ばれてしまい、NDL Searchへの既刊数検索
    /// （タイトル一致ベース）が空振りして既刊数が「不明」になったり戻ったりする不具合があった。
    /// 多数派の表記が常に安定して選ばれることを確認する。
    func test_calculateAll_seriesNamePicksMajorityVariantDeterministically() throws {
        try insertOwned(seriesName: "HUNTER×HUNTER", volume: 1)
        try insertOwned(seriesName: "HUNTER×HUNTER", volume: 2)
        try insertOwned(seriesName: "HUNTER×HUNTER", volume: 3)
        try insertOwned(seriesName: "hunter×hunter", volume: 4) // 少数派の表記ゆれ（同一seriesKeyにグルーピングされる）

        let progress = try calculator.calculateAll()
            .first { $0.seriesKey == SeriesKeyNormalizer.normalize("HUNTER×HUNTER") }
        XCTAssertEqual(progress?.seriesName, "HUNTER×HUNTER", "多数派の表記が代表シリーズ名として選ばれること")
    }

    /// 代表シリーズ名の出現数が同数の場合でも、実行のたびに異なる表記が選ばれないこと
    /// （文字列としてより小さい方を選ぶ、というタイブレークの決定性を確認する）。
    func test_calculateAll_seriesNameTieBreak_deterministicAcrossRuns() throws {
        try insertOwned(seriesName: "ALPHA", volume: 1)
        try insertOwned(seriesName: "Alpha", volume: 2)

        let progress = try calculator.calculateAll()
            .first { $0.seriesKey == SeriesKeyNormalizer.normalize("Alpha") }
        XCTAssertEqual(progress?.seriesName, "ALPHA", "同数の場合は常に同じ表記が選ばれ、実行ごとに変わらないこと")
    }

    /// 回帰テスト: 上巻/中巻/下巻等、同じ巻数を複数の本が共有する場合に、
    /// NDLSearchServiceが構築したタイトル末尾のマーカー（例:「1(上)」）を表示ラベルに反映し、
    /// 本棚の巻一覧で見分けられるようにすること。
    func test_volumes_displayLabel_reflectsSplitVolumeMarkerFromTitle() throws {
        try repository.insert(BookDraft(
            isbn: nil, title: "転生したらスライムだった件 1(上)", seriesName: "転生したらスライムだった件",
            volumeNumber: 1, coverImageURL: nil, status: .owned, readStatus: .unread, metadataFetched: true
        ))
        try repository.insert(BookDraft(
            isbn: nil, title: "転生したらスライムだった件 1(下)", seriesName: "転生したらスライムだった件",
            volumeNumber: 1, coverImageURL: nil, status: .owned, readStatus: .unread, metadataFetched: true
        ))

        let progress = try calculator.calculateAll().first { $0.seriesName == "転生したらスライムだった件" }
        let labels = try XCTUnwrap(progress?.volumes.map(\.displayLabel))
        XCTAssertEqual(Set(labels), ["1巻（上）", "1巻（下）"], "同じ巻数でもマーカーで見分けられること")
    }

    // MARK: - seriesKeysNeedingRefresh（既刊数「不明」の再チェック）

    /// 回帰テスト: 既刊総数が「不明」（nil）でキャッシュされている場合、キャッシュの鮮度
    /// （30日）に関わらず常に再チェック対象とすること。蔵書を1冊ずつ登録していく実際の
    /// 使われ方では、シリーズの一部しか登録されていないタイミングでたまたま既刊数チェックが
    /// 走り「不明」がキャッシュされてしまうことがあるが、それを最大30日間放置せず、
    /// 残りの巻を登録し終えた次回起動時に自動で再チェックできるようにする。
    func test_seriesKeysNeedingRefresh_cachedAsUnknown_alwaysNeedsRefreshRegardlessOfFreshness() throws {
        try insertOwned(seriesName: "三体", volume: 1)
        try cache.upsert(seriesKey: SeriesKeyNormalizer.normalize("三体"), totalVolumes: nil) // たった今キャッシュされた「不明」

        let keys = try calculator.seriesKeysNeedingRefresh()
        XCTAssertTrue(keys.contains(SeriesKeyNormalizer.normalize("三体")), "「不明」はキャッシュが新しくても再チェック対象とすること")
    }

    func test_seriesKeysNeedingRefresh_cachedWithKnownTotal_respectsFreshnessWindow() throws {
        try insertOwned(seriesName: "三体", volume: 1)
        try cache.upsert(seriesKey: SeriesKeyNormalizer.normalize("三体"), totalVolumes: 3) // たった今キャッシュされた既知の値

        let keys = try calculator.seriesKeysNeedingRefresh()
        XCTAssertFalse(keys.contains(SeriesKeyNormalizer.normalize("三体")), "既知の値はキャッシュが新しければ再チェック不要のままとすること")
    }

    /// 本棚統合画面の「登録が新しい順」ソート用。シリーズ内で最も新しく登録された巻の日時が
    /// シリーズ自体の登録日時として使われること。
    func test_latestRegisteredAt_usesMostRecentlyRegisteredVolume() throws {
        let vol1 = try insertOwned(seriesName: "三体", volume: 1)

        Thread.sleep(forTimeInterval: 0.01)
        let vol2 = try insertOwned(seriesName: "三体", volume: 2)

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        XCTAssertEqual(progress?.latestRegisteredAt, vol2.registeredAt)
        XCTAssertGreaterThan(vol2.registeredAt, vol1.registeredAt)
    }

    func test_statusCounts_summarizesByUnifiedStatus() throws {
        try insertOwned(seriesName: "三体", volume: 1) // unread
        let vol2 = try repository.insert(BookDraft(
            isbn: nil, title: "三体 2", seriesName: "三体", volumeNumber: 2,
            coverImageURL: nil, status: .owned, readStatus: .finished, metadataFetched: true
        ))
        try repository.update(
            id: vol2.id,
            changes: BookChanges(
                title: vol2.title, seriesName: vol2.seriesName, volumeNumber: vol2.volumeNumber,
                isbn: vol2.isbn, coverImageURL: vol2.coverImageURL, status: .owned, readStatus: .finished
            )
        )

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        let counts = Dictionary(uniqueKeysWithValues: (progress?.statusCounts ?? []).map { ($0.status, $0.count) })
        XCTAssertEqual(counts[.unread], 1)
        XCTAssertEqual(counts[.finished], 1)
        XCTAssertNil(counts[.reading])
    }
}
