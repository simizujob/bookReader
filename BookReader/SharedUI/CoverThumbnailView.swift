import SwiftUI

/// 表紙画像のサムネイル表示。取得できない・URLが無い場合は本のアイコンをプレースホルダーとして表示する。
struct CoverThumbnailView: View {
    let url: String?
    var width: CGFloat = 40
    var height: CGFloat = 56

    var body: some View {
        let placeholder = RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "book.closed").foregroundStyle(.secondary)
            }

        if let url, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            placeholder.frame(width: width, height: height)
        }
    }
}
