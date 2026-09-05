import Foundation

/// シリーズ内の1巻分のステータス表示用エントリ（本棚統合画面の巻別ステータス表示・変更に使用）。
struct SeriesVolumeEntry: Identifiable, Equatable {
    let bookID: UUID
    let volumeNumber: Int
    let unifiedStatus: UnifiedStatus
    let registeredAt: Date
    var id: UUID { bookID }
}

/// シリーズ単位の所持状況（Bookから導出）。詳細設計書4.2参照。
struct SeriesProgress: Identifiable, Equatable {
    var id: String { seriesKey }
    let seriesKey: String
    let seriesName: String
    let ownedVolumes: [Int]
    /// nilは「既刊総数不明」（Open Libraryから取得できなかった場合のフォールバック）
    let missingVolumes: [Int]?
    /// nilは「不明」。UIでは進捗バーを表示せず「不明」と表示する
    let completionRate: Double?
    let nextVolumeToBuy: Int?
    /// nextVolumeToBuyに対応するwishlist登録済みBookのISBN（あれば）
    let nextVolumeISBN: String?
    /// シリーズに属する各巻（所持・気になる本の両方）のステータス。巻数昇順。
    let volumes: [SeriesVolumeEntry]

    /// 完結率が閾値を超えた場合のポジティブ強調表示（要件定義書F-05）
    var isNearCompletion: Bool {
        guard let rate = completionRate else { return false }
        return rate >= 0.8 || (missingVolumes?.count ?? .max) <= 1
    }

    /// 本棚統合画面での「登録が新しい順」ソート用。シリーズ内で最も新しく登録された巻の日時を
    /// シリーズ自体の登録日時とみなす（直近で巻が追加されたシリーズほど上位に来るようにするため）。
    var latestRegisteredAt: Date {
        volumes.map(\.registeredAt).max() ?? .distantPast
    }

    /// 本棚統合画面でのステータス内訳表示用（例: 未読2・読書中1・読了3）
    var statusCounts: [(status: UnifiedStatus, count: Int)] {
        let grouped = Dictionary(grouping: volumes, by: \.unifiedStatus).mapValues(\.count)
        return UnifiedStatus.allCases.compactMap { status in
            guard let count = grouped[status], count > 0 else { return nil }
            return (status, count)
        }
    }
}
