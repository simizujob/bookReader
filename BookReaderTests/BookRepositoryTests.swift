import XCTest
import CoreData
@testable import BookReader

final class BookRepositoryTests: XCTestCase {
    private var persistence: PersistenceController!
    private var scheduler: MockReminderScheduler!
    private var repository: CoreDataBookRepository!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
        scheduler = MockReminderScheduler()
        repository = CoreDataBookRepository(
            context: persistence.container.viewContext,
            notificationService: scheduler
        )
    }

    private func draft(
        isbn: String? = "9784041031400",
        title: String = "鬼滅の刃 19",
        seriesName: String? = "鬼滅の刃",
        volumeNumber: Int? = 19,
        status: OwnershipStatus = .owned,
        readStatus: ReadStatus = .unread
    ) -> BookDraft {
        BookDraft(
            isbn: isbn,
            title: title,
            seriesName: seriesName,
            volumeNumber: volumeNumber,
            coverImageURL: nil,
            status: status,
            readStatus: readStatus,
            metadataFetched: true
        )
    }

    // MARK: - insert / find

    func test_insert_thenFindByISBN_returnsSameBook() throws {
        let inserted = try repository.insert(draft())
        let found = try repository.find(isbn: "9784041031400")
        XCTAssertEqual(found?.id, inserted.id)
        XCTAssertEqual(found?.seriesKey, SeriesKeyNormalizer.normalize("鬼滅の刃"))
    }

    func test_insertBatch_registersAllBooks() throws {
        let drafts = [
            draft(isbn: "9781111111111", title: "本A"),
            draft(isbn: "9782222222222", title: "本B")
        ]
        let inserted = try repository.insertBatch(drafts)
        XCTAssertEqual(inserted.count, 2)
        XCTAssertEqual(try repository.fetchAll().count, 2)
    }

    // MARK: - judge (F-02)

    func test_judge_ownedISBN_returnsOwned() throws {
        try repository.insert(draft(isbn: "9784041031400"))
        let result = try repository.judge(isbn: "9784041031400")
        XCTAssertEqual(result, .owned)
    }

    func test_judge_unknownISBN_returnsNotOwnedWithoutEditionGuess() throws {
        let result = try repository.judge(isbn: "9789999999999")
        XCTAssertEqual(result, .notOwned(possibleEdition: nil))
    }

    // MARK: - isDuplicate / fuzzyMatch

    func test_isDuplicate_sameISBN_true() throws {
        try repository.insert(draft(isbn: "9784041031400"))
        XCTAssertTrue(try repository.isDuplicate(isbn: "9784041031400", title: "別タイトルでも"))
    }

    func test_isDuplicate_differentISBNHighSimilarityTitle_true() throws {
        try repository.insert(draft(isbn: "9784041031400", title: "鬼滅の刃 19"))
        // 単行本(9784041031400) と 文庫版(別ISBN) のような版違いケース
        XCTAssertTrue(try repository.isDuplicate(isbn: "9785555555555", title: "鬼滅の刃 19"))
    }

    func test_isDuplicate_unrelatedBook_false() throws {
        try repository.insert(draft(isbn: "9784041031400", title: "鬼滅の刃 19"))
        XCTAssertFalse(try repository.isDuplicate(isbn: "9786666666666", title: "三体"))
    }

    // MARK: - update / delete

    func test_update_changesTitleAndVolume_recalculatesSeriesKey() throws {
        let inserted = try repository.insert(draft())
        let updated = try repository.update(
            id: inserted.id,
            changes: BookChanges(
                title: "進撃の巨人 5",
                seriesName: "進撃の巨人",
                volumeNumber: 5,
                status: .owned,
                readStatus: .unread
            )
        )
        XCTAssertEqual(updated.seriesKey, SeriesKeyNormalizer.normalize("進撃の巨人"))
        XCTAssertEqual(updated.volumeNumber, 5)
    }

    func test_delete_removesBookFromSubsequentFetches() throws {
        let inserted = try repository.insert(draft())
        try repository.delete(id: inserted.id)
        XCTAssertNil(try repository.find(id: inserted.id))
        XCTAssertEqual(try repository.fetchAll().count, 0)
    }

    func test_delete_unknownID_throwsNotFound() {
        let unknownID = UUID()
        XCTAssertThrowsError(try repository.delete(id: unknownID)) { error in
            XCTAssertEqual(error as? PersistenceError, .notFound(unknownID))
        }
    }

    // MARK: - 通知スケジュール遷移ルール（詳細設計書5.6）

    func test_insertOwnedUnread_schedulesReminder() throws {
        let book = try repository.insert(draft(status: .owned, readStatus: .unread))
        XCTAssertEqual(scheduler.scheduledBookIDs, [book.id])
    }

    func test_insertWishlist_doesNotScheduleReminder() throws {
        try repository.insert(draft(status: .wishlist))
        XCTAssertTrue(scheduler.scheduledBookIDs.isEmpty)
    }

    func test_markAsFinished_cancelsReminder() throws {
        let book = try repository.insert(draft(status: .owned, readStatus: .unread))
        scheduler = MockReminderScheduler() // reset to isolate this transition
        repository = CoreDataBookRepository(context: persistence.container.viewContext, notificationService: scheduler)

        try repository.update(
            id: book.id,
            changes: BookChanges(title: book.title, seriesName: book.seriesName, volumeNumber: book.volumeNumber, status: .owned, readStatus: .finished)
        )
        XCTAssertEqual(scheduler.cancelledBookIDs, [book.id])
    }

    func test_wishlistToOwned_schedulesReminder() throws {
        let book = try repository.insert(draft(status: .wishlist))
        scheduler = MockReminderScheduler()
        repository = CoreDataBookRepository(context: persistence.container.viewContext, notificationService: scheduler)

        try repository.update(
            id: book.id,
            changes: BookChanges(title: book.title, seriesName: book.seriesName, volumeNumber: book.volumeNumber, status: .owned, readStatus: .unread)
        )
        XCTAssertEqual(scheduler.scheduledBookIDs, [book.id])
    }

    func test_delete_cancelsReminder() throws {
        let book = try repository.insert(draft(status: .owned, readStatus: .unread))
        scheduler = MockReminderScheduler()
        repository = CoreDataBookRepository(context: persistence.container.viewContext, notificationService: scheduler)

        try repository.delete(id: book.id)
        XCTAssertEqual(scheduler.cancelledBookIDs, [book.id])
    }

    // MARK: - applyMetadata（バックフィル、詳細設計書4.3a/4.8）

    func test_applyMetadata_parsesSeriesAndVolumeFromTitle() throws {
        let book = try repository.insert(
            BookDraft(
                isbn: "9784041031400",
                title: "ISBN: 9784041031400",
                seriesName: nil,
                volumeNumber: nil,
                coverImageURL: nil,
                status: .owned,
                readStatus: .unread,
                metadataFetched: false
            )
        )
        try repository.applyMetadata(id: book.id, title: "鬼滅の刃 19", coverImageURL: "https://example.com/cover.jpg")

        let updated = try repository.find(id: book.id)
        XCTAssertEqual(updated?.seriesName, "鬼滅の刃")
        XCTAssertEqual(updated?.volumeNumber, 19)
        XCTAssertEqual(updated?.seriesKey, SeriesKeyNormalizer.normalize("鬼滅の刃"))
        XCTAssertEqual(updated?.metadataFetched, true)
    }

    func test_fetchPendingMetadata_returnsOnlyUnfetchedBooks() throws {
        try repository.insert(draft(isbn: "9781111111111", title: "取得済み"))
        try repository.insert(
            BookDraft(
                isbn: "9782222222222",
                title: "ISBN: 9782222222222",
                seriesName: nil,
                volumeNumber: nil,
                coverImageURL: nil,
                status: .owned,
                readStatus: .unread,
                metadataFetched: false
            )
        )
        let pending = try repository.fetchPendingMetadata()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.isbn, "9782222222222")
    }
}
