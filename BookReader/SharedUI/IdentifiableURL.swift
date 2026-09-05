import Foundation

/// SFSafariViewControllerを`.sheet(item:)`で表示するためのラッパー。
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
