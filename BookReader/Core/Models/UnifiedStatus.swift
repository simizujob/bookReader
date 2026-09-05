import Foundation

/// 「気になる本棚」と「積読リスト」の統合に伴う統一ステータス。
/// OwnershipStatus.wishlistを「未購入」として扱い、所持後のReadStatus（未読/読書中/読了）と
/// 合わせて1つの軸にまとめる。ステータス変更は2タップ（ピルをタップ→メニューから選択）で
/// 完了できるようにするためのUI表示・変更ロジックの基盤。
enum UnifiedStatus: Int, CaseIterable, Comparable, Equatable {
    case wishlist
    case unread
    case reading
    case finished

    static func < (lhs: UnifiedStatus, rhs: UnifiedStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func resolve(status: OwnershipStatus, readStatus: ReadStatus) -> UnifiedStatus {
        guard status == .owned else { return .wishlist }
        switch readStatus {
        case .unread: return .unread
        case .reading: return .reading
        case .finished: return .finished
        }
    }

    /// このステータスへ変更する際に設定すべき(status, readStatus)の組。
    var bookStatusPair: (status: OwnershipStatus, readStatus: ReadStatus) {
        switch self {
        case .wishlist: return (.wishlist, .unread)
        case .unread: return (.owned, .unread)
        case .reading: return (.owned, .reading)
        case .finished: return (.owned, .finished)
        }
    }

    var label: String {
        switch self {
        case .wishlist: return "未購入"
        case .unread: return "未読"
        case .reading: return "読書中"
        case .finished: return "読了"
        }
    }
}

extension Book {
    var unifiedStatus: UnifiedStatus {
        UnifiedStatus.resolve(status: status, readStatus: readStatus)
    }
}
