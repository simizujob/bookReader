import Foundation

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

    /// 完結率が閾値を超えた場合のポジティブ強調表示（要件定義書F-05）
    var isNearCompletion: Bool {
        guard let rate = completionRate else { return false }
        return rate >= 0.8 || (missingVolumes?.count ?? .max) <= 1
    }
}
