import CoreData
import WidgetKit

protocol BookRepository {
    // MARK: - 取得
    func fetchAll() throws -> [Book]
    func fetchBySegment(_ readStatus: ReadStatus) throws -> [Book]
    func find(id: UUID) throws -> Book?
    func find(isbn: String) throws -> Book?
    func find(seriesKey: String, volumeNumber: Int) throws -> Book?
    func fetchPendingMetadata() throws -> [Book]

    // MARK: - 判定（F-02）。オフラインで確実に返せる範囲のみを扱う（詳細設計書4.1a）
    func judge(isbn: String) throws -> JudgeResult

    // MARK: - あいまい一致（F-02版違い警告 / F-03確認UI 共用）
    func fuzzyMatch(title: String, excludingISBN: String?) throws -> FuzzyMatchResult?

    // MARK: - 重複判定（F-01/F-03/F-09 共通）
    func isDuplicate(isbn: String?, title: String) throws -> Bool

    // MARK: - 書き込み
    @discardableResult func insert(_ draft: BookDraft) throws -> Book
    @discardableResult func insertBatch(_ drafts: [BookDraft]) throws -> [Book]
    @discardableResult func update(id: UUID, changes: BookChanges) throws -> Book
    func delete(id: UUID) throws
    func applyMetadata(id: UUID, metadata: BookMetadata) throws
}

/// CoreData実装。詳細設計書4.1参照。
/// insert/insertBatch/update/delete/applyMetadataの後処理（通知スケジュール・Widget更新）を
/// afterWrite/afterDeleteに一元化し、呼び忘れを構造的に防ぐ。
final class CoreDataBookRepository: BookRepository {
    private let context: NSManagedObjectContext
    private let notificationService: ReminderScheduling
    private let fuzzyMatchThreshold = 0.8
    private let widgetKind = "TsundokuSummaryWidget"

    init(context: NSManagedObjectContext, notificationService: ReminderScheduling = NotificationService()) {
        self.context = context
        self.notificationService = notificationService
    }

    // MARK: - 取得

    func fetchAll() throws -> [Book] {
        let request = BookEntity.fetchRequest()
        return try context.performAndWait { try context.fetch(request).map(Self.map) }
    }

    func fetchBySegment(_ readStatus: ReadStatus) throws -> [Book] {
        let request = BookEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "status == %@ AND readStatus == %@",
            OwnershipStatus.owned.rawValue,
            readStatus.rawValue
        )
        return try context.performAndWait { try context.fetch(request).map(Self.map) }
    }

    func find(id: UUID) throws -> Book? {
        try findEntity(id: id).map(Self.map)
    }

    func find(isbn: String) throws -> Book? {
        let request = BookEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isbn == %@", isbn)
        request.fetchLimit = 1
        return try context.performAndWait { try context.fetch(request).first.map(Self.map) }
    }

    func find(seriesKey: String, volumeNumber: Int) throws -> Book? {
        let request = BookEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "seriesKey == %@ AND volumeNumber == %d",
            seriesKey, volumeNumber
        )
        request.fetchLimit = 1
        return try context.performAndWait { try context.fetch(request).first.map(Self.map) }
    }

    func fetchPendingMetadata() throws -> [Book] {
        let request = BookEntity.fetchRequest()
        request.predicate = NSPredicate(format: "metadataFetched == NO")
        return try context.performAndWait { try context.fetch(request).map(Self.map) }
    }

    // MARK: - 判定

    func judge(isbn: String) throws -> JudgeResult {
        if let existing = try find(isbn: isbn), existing.status == .owned {
            return .owned(existing)
        }
        // このISBN単独ではタイトルが未知のため、版違い判定はまだ行わない（詳細設計書4.1a）
        return .notOwned(possibleEdition: nil)
    }

    func fuzzyMatch(title: String, excludingISBN: String?) throws -> FuzzyMatchResult? {
        let all = try fetchAll()
        var best: FuzzyMatchResult?
        for book in all {
            if let excludingISBN, book.isbn == excludingISBN { continue }
            let similarity = TitleMatcher.similarity(title, book.title)
            guard similarity >= fuzzyMatchThreshold else { continue }
            if best == nil || similarity > best!.similarity {
                best = FuzzyMatchResult(matchedBook: book, similarity: similarity)
            }
        }
        return best
    }

    func isDuplicate(isbn: String?, title: String) throws -> Bool {
        if let isbn, try find(isbn: isbn) != nil {
            return true
        }
        return try fuzzyMatch(title: title, excludingISBN: isbn) != nil
    }

    // MARK: - 書き込み

    @discardableResult
    func insert(_ draft: BookDraft) throws -> Book {
        try context.performAndWait {
            let entity = BookEntity(context: context)
            entity.id = UUID()
            entity.registeredAt = Date()
            apply(draft, to: entity)

            try save()
            let book = Self.map(entity)
            afterWrite(new: book, previous: nil)
            return book
        }
    }

    @discardableResult
    func insertBatch(_ drafts: [BookDraft]) throws -> [Book] {
        try context.performAndWait {
            var books: [Book] = []
            for draft in drafts {
                let entity = BookEntity(context: context)
                entity.id = UUID()
                entity.registeredAt = Date()
                apply(draft, to: entity)
                books.append(Self.map(entity))
            }
            try save()
            for book in books {
                afterWrite(new: book, previous: nil)
            }
            return books
        }
    }

    @discardableResult
    func update(id: UUID, changes: BookChanges) throws -> Book {
        try context.performAndWait {
            guard let entity = try findEntity(id: id) else {
                throw PersistenceError.notFound(id)
            }
            let previous = Self.map(entity)

            entity.title = changes.title
            entity.seriesName = changes.seriesName
            entity.seriesKey = changes.seriesName.map { SeriesKeyNormalizer.normalize($0) }
            entity.volumeNumber = changes.volumeNumber.map { NSNumber(value: $0) }
            entity.isbn = changes.isbn
            entity.coverImageURL = changes.coverImageURL
            entity.status = changes.status.rawValue
            entity.readStatus = changes.readStatus.rawValue

            try save()
            let updated = Self.map(entity)
            afterWrite(new: updated, previous: previous)
            return updated
        }
    }

    func delete(id: UUID) throws {
        try context.performAndWait {
            guard let entity = try findEntity(id: id) else {
                throw PersistenceError.notFound(id)
            }
            let deleted = Self.map(entity)
            context.delete(entity)
            try save()
            afterDelete(deleted)
        }
    }

    func applyMetadata(id: UUID, metadata: BookMetadata) throws {
        try context.performAndWait {
            guard let entity = try findEntity(id: id) else {
                throw PersistenceError.notFound(id)
            }
            let resolved = metadata.resolvedSeriesInfo
            entity.title = metadata.title
            entity.coverImageURL = metadata.coverImageURL
            entity.seriesName = resolved.seriesName
            entity.seriesKey = resolved.seriesName.map { SeriesKeyNormalizer.normalize($0) }
            entity.volumeNumber = resolved.volumeNumber.map { NSNumber(value: $0) }
            entity.metadataFetched = true
            try save()
        }
    }

    // MARK: - Private

    private func findEntity(id: UUID) throws -> BookEntity? {
        let request = BookEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.performAndWait { try context.fetch(request).first }
    }

    private func apply(_ draft: BookDraft, to entity: BookEntity) {
        entity.isbn = draft.isbn
        entity.title = draft.title
        entity.seriesName = draft.seriesName
        entity.seriesKey = draft.seriesName.map { SeriesKeyNormalizer.normalize($0) }
        entity.volumeNumber = draft.volumeNumber.map { NSNumber(value: $0) }
        entity.coverImageURL = draft.coverImageURL
        entity.status = draft.status.rawValue
        entity.readStatus = draft.readStatus.rawValue
        entity.metadataFetched = draft.metadataFetched
    }

    private func save() throws {
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }

    /// 通知スケジュール/キャンセルの遷移ルール（詳細設計書5.6）とWidget更新を一元的に処理する。
    private func afterWrite(new book: Book, previous: Book?) {
        switch (previous?.status, previous?.readStatus, book.status, book.readStatus) {
        case (nil, _, .owned, .unread):
            // 新規登録（.owned, .unread）
            notificationService.scheduleReminder(for: book)
        case (.wishlist, _, .owned, .unread):
            // wishlist → owned への変更
            notificationService.scheduleReminder(for: book)
        case (_, _, _, .finished):
            notificationService.cancelReminder(bookID: book.id)
        case (.owned, _, .wishlist, _):
            notificationService.cancelReminder(bookID: book.id)
        default:
            break
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private func afterDelete(_ deleted: Book) {
        notificationService.cancelReminder(bookID: deleted.id)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// CoreDataの自動生成プロパティはObject型（String/Date/UUID等）がすべてOptionalになるため、
    /// insert時に必ず設定される不変条件を前提としつつ、防御的にフォールバック値で吸収する。
    private static func map(_ entity: BookEntity) -> Book {
        Book(
            id: entity.id ?? UUID(),
            isbn: entity.isbn,
            title: entity.title ?? "",
            seriesName: entity.seriesName,
            seriesKey: entity.seriesKey,
            volumeNumber: entity.volumeNumber?.intValue,
            coverImageURL: entity.coverImageURL,
            status: OwnershipStatus(rawValue: entity.status ?? "") ?? .owned,
            readStatus: ReadStatus(rawValue: entity.readStatus ?? "") ?? .unread,
            registeredAt: entity.registeredAt ?? Date(),
            lastOpenedAt: entity.lastOpenedAt,
            metadataFetched: entity.metadataFetched
        )
    }
}
