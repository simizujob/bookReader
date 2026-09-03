import Foundation

/// 蔵書レコードのドメインモデル。CoreDataのBookEntityから都度マッピングして生成する。
/// NSManagedObjectをView/ViewModelに漏らさないため、Repository層より上ではこの型のみを使用する。
struct Book: Identifiable, Equatable {
    let id: UUID
    var isbn: String?
    var title: String
    var seriesName: String?
    var seriesKey: String?
    var volumeNumber: Int?
    var coverImageURL: String?
    var status: OwnershipStatus
    var readStatus: ReadStatus
    var registeredAt: Date
    var lastOpenedAt: Date?
    var metadataFetched: Bool

    /// 積読リスト（F-04）表示用の経過日数
    func elapsedDays(from now: Date = Date()) -> Int {
        Calendar.current.dateComponents([.day], from: registeredAt, to: now).day ?? 0
    }
}
