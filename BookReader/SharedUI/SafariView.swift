import SwiftUI
import SafariServices

/// 書店検索の購入導線（F-05）。詳細設計書2.2「SFSafariViewControllerをUIViewControllerRepresentableでラップ」。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
