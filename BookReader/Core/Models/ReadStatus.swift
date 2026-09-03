import Foundation

enum ReadStatus: String, Codable, Equatable, CaseIterable {
    case unread
    case reading
    case finished
}
