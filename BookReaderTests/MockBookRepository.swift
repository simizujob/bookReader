import Foundation
@testable import BookReader

/// CoreDataを使わない軽量なテストダブル。ViewModel層の単体テストで使用する。
/// Repository自体の永続化ロジック（CoreDataマッピング等）はBookRepositoryTestsで別途検証している。
final class MockBookRepository: BookRepository {
    private(set) var books: [Book] = []
    private let fuzzyMatchThreshold = 0.8

    private(set) var insertedDrafts: [BookDraft] = []
    private(set) var updatedIDs: [UUID] = []
    private(set) var deletedIDs: [UUID] = []

    func seed(_ book: Book) {
        books.append(book)
    }

    func fetchAll() throws -> [Book] { books }

    func fetchBySegment(_ readStatus: ReadStatus) throws -> [Book] {
        books.filter { $0.status == .owned && $0.readStatus == readStatus }
    }

    func find(id: UUID) throws -> Book? {
        books.first { $0.id == id }
    }

    func find(isbn: String) throws -> Book? {
        books.first { $0.isbn == isbn }
    }

    func find(seriesKey: String, volumeNumber: Int) throws -> Book? {
        books.first { $0.seriesKey == seriesKey && $0.volumeNumber == volumeNumber }
    }

    func fetchPendingMetadata() throws -> [Book] {
        books.filter { !$0.metadataFetched }
    }

    func judge(isbn: String) throws -> JudgeResult {
        if let existing = try find(isbn: isbn), existing.status == .owned {
            return .owned
        }
        return .notOwned(possibleEdition: nil)
    }

    func fuzzyMatch(title: String, excludingISBN: String?) throws -> FuzzyMatchResult? {
        var best: FuzzyMatchResult?
        for book in books {
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
        if let isbn, try find(isbn: isbn) != nil { return true }
        return try fuzzyMatch(title: title, excludingISBN: isbn) != nil
    }

    @discardableResult
    func insert(_ draft: BookDraft) throws -> Book {
        insertedDrafts.append(draft)
        let book = Book(
            id: UUID(),
            isbn: draft.isbn,
            title: draft.title,
            seriesName: draft.seriesName,
            seriesKey: draft.seriesName.map { SeriesKeyNormalizer.normalize($0) },
            volumeNumber: draft.volumeNumber,
            coverImageURL: draft.coverImageURL,
            status: draft.status,
            readStatus: draft.readStatus,
            registeredAt: Date(),
            lastOpenedAt: nil,
            metadataFetched: draft.metadataFetched
        )
        books.append(book)
        return book
    }

    @discardableResult
    func insertBatch(_ drafts: [BookDraft]) throws -> [Book] {
        try drafts.map { try insert($0) }
    }

    @discardableResult
    func update(id: UUID, changes: BookChanges) throws -> Book {
        guard let index = books.firstIndex(where: { $0.id == id }) else {
            throw PersistenceError.notFound(id)
        }
        updatedIDs.append(id)
        var book = books[index]
        book.title = changes.title
        book.seriesName = changes.seriesName
        book.seriesKey = changes.seriesName.map { SeriesKeyNormalizer.normalize($0) }
        book.volumeNumber = changes.volumeNumber
        book.status = changes.status
        book.readStatus = changes.readStatus
        books[index] = book
        return book
    }

    func delete(id: UUID) throws {
        guard let index = books.firstIndex(where: { $0.id == id }) else {
            throw PersistenceError.notFound(id)
        }
        deletedIDs.append(id)
        books.remove(at: index)
    }

    func applyMetadata(id: UUID, title: String, coverImageURL: String?) throws {
        guard let index = books.firstIndex(where: { $0.id == id }) else {
            throw PersistenceError.notFound(id)
        }
        let parsed = TitleParser.parse(title)
        var book = books[index]
        book.title = parsed.title
        book.coverImageURL = coverImageURL
        book.seriesName = parsed.seriesName
        book.seriesKey = parsed.seriesName.map { SeriesKeyNormalizer.normalize($0) }
        book.volumeNumber = parsed.volumeNumber
        book.metadataFetched = true
        books[index] = book
    }
}
