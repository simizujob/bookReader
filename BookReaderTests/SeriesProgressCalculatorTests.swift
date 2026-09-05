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

    private func insertOwned(seriesName: String, volume: Int, isbn: String? = nil) throws {
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
        XCTAssertEqual(volumes.last, SeriesVolumeEntry(bookID: inserted.id, volumeNumber: 2, unifiedStatus: .wishlist))
    }

    func test_statusCounts_summarizesByUnifiedStatus() throws {
        try insertOwned(seriesName: "三体", volume: 1) // unread
        let vol2 = try repository.insert(BookDraft(
            isbn: nil, title: "三体 2", seriesName: "三体", volumeNumber: 2,
            coverImageURL: nil, status: .owned, readStatus: .finished, metadataFetched: true
        ))
        try repository.update(
            id: vol2.id,
            changes: BookChanges(title: vol2.title, seriesName: vol2.seriesName, volumeNumber: vol2.volumeNumber, status: .owned, readStatus: .finished)
        )

        let progress = try calculator.calculateAll().first { $0.seriesName == "三体" }
        let counts = Dictionary(uniqueKeysWithValues: (progress?.statusCounts ?? []).map { ($0.status, $0.count) })
        XCTAssertEqual(counts[.unread], 1)
        XCTAssertEqual(counts[.finished], 1)
        XCTAssertNil(counts[.reading])
    }
}
