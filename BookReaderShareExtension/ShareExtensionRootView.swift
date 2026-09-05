import SwiftUI

/// Amazonの商品ページから共有された場合の判定結果画面（ShareViewControllerがホストする）。
/// カメラを使わない点を除き、買う前チェック（PreCheckView）と同じ判定結果表現を踏襲する。
struct ShareExtensionRootView: View {
    @StateObject private var viewModel: ShareExtensionViewModel
    let sharedURL: URL?
    /// タグ付きURLでAmazonへ戻ってから拡張を終了する／そのまま終了する、いずれもここに委譲する。
    let onFinish: (URL?) -> Void

    init(bookRepository: BookRepository, sharedURL: URL?, onFinish: @escaping (URL?) -> Void) {
        _viewModel = StateObject(wrappedValue: ShareExtensionViewModel(bookRepository: bookRepository))
        self.sharedURL = sharedURL
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                content
                Spacer()
            }
            .padding()
            .navigationTitle("買う前チェック")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onFinish(nil) }
                }
            }
        }
        .onAppear {
            viewModel.handle(sharedURL: sharedURL)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loadingURL:
            ProgressView()
        case .unrecognized:
            Text("Amazonの本の商品ページを認識できませんでした")
                .foregroundStyle(.secondary)
        case .error(let message):
            Text(message).foregroundStyle(.red)
        case .judged(let result):
            judgedResult(result)
        }
    }

    @ViewBuilder
    private func judgedResult(_ result: JudgeResult) -> some View {
        switch result {
        case .owned:
            resultCard(title: "持っています", tint: .green, systemImage: "checkmark.circle.fill")
            returnToAmazonButton
        case .wishlisted:
            resultCard(title: "気になるリストに登録済みです", tint: .blue, systemImage: "bookmark.fill")
            returnToAmazonButton
        case .notOwned:
            resultCard(title: "持っていません", tint: .secondary, systemImage: "xmark.circle")
            HStack(spacing: 12) {
                if viewModel.isLoadingMetadata {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button("気になるリストへ登録") {
                        viewModel.addToWishlist()
                        onFinish(viewModel.amazonReturnURL)
                    }
                    .buttonStyle(.borderedProminent)
                }
                returnToAmazonButton
            }
        }
    }

    private var returnToAmazonButton: some View {
        Button("Amazonに戻る") {
            onFinish(viewModel.amazonReturnURL)
        }
        .buttonStyle(.bordered)
    }

    private func resultCard(title: String, tint: Color, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(title).font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
