import Foundation

/// 新規登録用の下書き。id/registeredAtはRepositoryが採番する。
struct BookDraft {
    var isbn: String?
    var title: String
    var seriesName: String?
    var volumeNumber: Int?
    var coverImageURL: String?
    var status: OwnershipStatus
    var readStatus: ReadStatus = .unread
    var metadataFetched: Bool
}

/// F-08編集フォームからの更新内容
struct BookChanges {
    var title: String
    var seriesName: String?
    var volumeNumber: Int?
    var isbn: String?
    var coverImageURL: String?
    var status: OwnershipStatus
    var readStatus: ReadStatus
}

struct FuzzyMatchResult: Equatable {
    let matchedBook: Book
    let similarity: Double
}

/// F-02買う前チェックの判定結果。オフラインで確実に返せる範囲のみを扱う（詳細設計書4.1a）。
/// .owned/.wishlistedは一致した蔵書レコードを保持し、画面下部の「スキャンした本」表示に使用する。
enum JudgeResult: Equatable {
    case owned(Book)
    /// 既に「気になる本棚」へ登録済み（未購入）。本棚には登録済みだが所持はしていない状態。
    case wishlisted(Book)
    case notOwned(possibleEdition: FuzzyMatchResult?)
}

enum PersistenceError: Error, Equatable {
    case saveFailed(String)
    case notFound(UUID)
}
