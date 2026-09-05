import Foundation

/// 本棚統合画面で「本」（単独本）と「シリーズ」を区別せず1つのリストとして扱うための表示アイテム。
enum ShelfItem: Identifiable, Equatable {
    case book(Book)
    case series(SeriesProgress)

    var id: String {
        switch self {
        case .book(let book): return "book-\(book.id.uuidString)"
        case .series(let series): return "series-\(series.seriesKey)"
        }
    }

    var sortTitle: String {
        switch self {
        case .book(let book): return book.title
        case .series(let series): return series.seriesName
        }
    }

    var latestRegisteredAt: Date {
        switch self {
        case .book(let book): return book.registeredAt
        case .series(let series): return series.latestRegisteredAt
        }
    }

    /// ステータスでソートする際の代表値。シリーズは巻の中で最も進捗が浅い（未購入に近い）
    /// ステータスを基準にする。「まだ手を付けていないものを目立たせる」という
    /// 積読管理アプリの目的に合わせるため、1巻でも読了していないシリーズは
    /// 読了済みシリーズより先に並ぶようにする。
    var sortStatus: UnifiedStatus {
        switch self {
        case .book(let book): return book.unifiedStatus
        case .series(let series): return series.volumes.map(\.unifiedStatus).min() ?? .wishlist
        }
    }

    func matches(searchText: String) -> Bool {
        sortTitle.localizedCaseInsensitiveContains(searchText)
    }
}

/// 本棚統合画面のソート条件。
enum ShelfSortOption: String, CaseIterable, Identifiable {
    case newest
    case title
    case status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "登録日時（新しい順）"
        case .title: return "タイトル・シリーズ名順"
        case .status: return "ステータス順"
        }
    }

    func sorted(_ items: [ShelfItem]) -> [ShelfItem] {
        switch self {
        case .newest:
            return items.sorted { $0.latestRegisteredAt > $1.latestRegisteredAt }
        case .title:
            return items.sorted {
                $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending
            }
        case .status:
            return items.sorted { $0.sortStatus < $1.sortStatus }
        }
    }
}
