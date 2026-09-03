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
    var status: OwnershipStatus
    var readStatus: ReadStatus
}

struct FuzzyMatchResult: Equatable {
    let matchedBook: Book
    let similarity: Double
}

/// F-02買う前チェックの判定結果。オフラインで確実に返せる範囲のみを扱う（詳細設計書4.1a）。
enum JudgeResult: Equatable {
    case owned
    case notOwned(possibleEdition: FuzzyMatchResult?)
}

enum PersistenceError: Error, Equatable {
    case saveFailed(String)
    case notFound(UUID)
}
