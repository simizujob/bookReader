import SwiftUI
import UIKit

struct PreCheckView: View {
    @StateObject private var viewModel: PreCheckViewModel
    @StateObject private var camera = CameraCaptureController()
    /// カメラに集中していてスキャン完了に気づけない、というフィードバックを受けての対応。
    /// 判定が確定した瞬間にカメラ映像の枠を光らせ、触感フィードバックも合わせて返す。
    @State private var scanFlashOpacity: Double = 0

    init(bookRepository: BookRepository) {
        _viewModel = StateObject(wrappedValue: PreCheckViewModel(bookRepository: bookRepository))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                cameraSection
                resultSection
                if viewModel.showManualSearch {
                    Text("うまく読み取れない場合は手動検索をお試しください")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("買う前チェック")
            // 「どの本を読み取ったか」を画面下部に常時表示する
            .safeAreaInset(edge: .bottom) {
                scannedBookFooter
            }
            .onAppear {
                camera.onFrame = { [weak viewModel] buffer in
                    Task { @MainActor in viewModel?.handleCapturedFrame(buffer) }
                }
                camera.start()
            }
            .onDisappear { camera.stop() }
            .onChange(of: viewModel.scanState) { _, newValue in
                guard case .scanning = newValue else {
                    flashScanCompletion()
                    return
                }
            }
        }
    }

    private func flashScanCompletion() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.15)) {
            scanFlashOpacity = 1
        }
        withAnimation(.easeIn(duration: 0.5).delay(0.15)) {
            scanFlashOpacity = 0
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black)
            if camera.isCameraAvailable {
                CameraPreviewView(session: camera.captureSession)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("カメラを利用できません")
                    .foregroundStyle(.white)
            }
            // スキャン完了時に枠を光らせ、カメラに集中していても気づけるようにする
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 8)
                .opacity(scanFlashOpacity)
        }
        .frame(height: 280)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch viewModel.scanState {
        case .scanning:
            Text("本のバーコードにカメラをかざしてください")
                .foregroundStyle(.secondary)
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                continueScanningButton
            }
        case .judged(let result):
            judgedResult(result)
        }
    }

    @ViewBuilder
    private func judgedResult(_ result: JudgeResult) -> some View {
        switch result {
        case .owned:
            VStack(alignment: .leading, spacing: 8) {
                resultCard(title: "持っています", subtitle: nil, tint: .green, systemImage: "checkmark.circle.fill")
                continueScanningButton
            }
        case .wishlisted:
            VStack(alignment: .leading, spacing: 8) {
                resultCard(
                    title: "気になるリストに登録済みです",
                    subtitle: "本棚では未購入として表示されています",
                    tint: .blue,
                    systemImage: "bookmark.fill"
                )
                continueScanningButton
            }
        case .notOwned:
            notOwnedResult
        }
    }

    @ViewBuilder
    private var notOwnedResult: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = viewModel.enrichedContext.partialSeriesInfo {
                resultCard(
                    title: "同じシリーズの一部を所持しています",
                    subtitle: "既刊〜\(info.ownedThrough)巻所持 ／ \(info.missingVolume)巻は未所持",
                    tint: .orange,
                    systemImage: "exclamationmark.triangle.fill"
                )
            } else {
                resultCard(
                    title: "持っていません",
                    subtitle: nil,
                    tint: .secondary,
                    systemImage: "xmark.circle"
                )
            }

            if let warning = viewModel.enrichedContext.editionWarning {
                Text("同じタイトルの別版を登録済みかもしれません（類似度\(Int(warning.similarity * 100))%）")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button("気になるリストへ登録") {
                    viewModel.addToWishlistAndContinueScanning()
                }
                .buttonStyle(.borderedProminent)

                Button("スキップ") {
                    viewModel.skipAndContinueScanning()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var continueScanningButton: some View {
        Button("次をスキャン") {
            viewModel.continueScanning()
        }
        .buttonStyle(.borderedProminent)
    }

    private func resultCard(title: String, subtitle: String?, tint: Color, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - スキャンした本（画面下部）

    /// 判定後、APIやレコードから取得したタイトル・表紙画像から「どの本を読み取ったか」を画面下部に表示する。
    /// 所持済み・気になるリスト登録済みの場合は登録時にキャッシュ済みのタイトル・表紙を、
    /// 未登録の場合は非同期取得中/取得結果を表示する。
    @ViewBuilder
    private var scannedBookFooter: some View {
        if let info = scannedBookInfo {
            HStack(spacing: 12) {
                coverThumbnail(url: info.coverImageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text("スキャンした本").font(.caption).foregroundStyle(.secondary)
                    Text(info.title).font(.subheadline).fontWeight(.semibold).lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .background(.thinMaterial)
        } else if viewModel.isLoadingMetadata {
            HStack(spacing: 12) {
                ProgressView()
                Text("本の情報を取得中…").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.thinMaterial)
        }
    }

    private struct ScannedBookInfo {
        let title: String
        let coverImageURL: String?
    }

    private var scannedBookInfo: ScannedBookInfo? {
        switch viewModel.scanState {
        case .judged(.owned(let book)), .judged(.wishlisted(let book)):
            return ScannedBookInfo(title: book.title, coverImageURL: book.coverImageURL)
        case .judged(.notOwned):
            guard let title = viewModel.enrichedContext.title else { return nil }
            return ScannedBookInfo(title: title, coverImageURL: viewModel.enrichedContext.coverImageURL)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func coverThumbnail(url: String?) -> some View {
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
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            placeholder.frame(width: 40, height: 56)
        }
    }
}
