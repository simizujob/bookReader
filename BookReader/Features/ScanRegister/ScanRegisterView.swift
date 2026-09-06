import SwiftUI
import UIKit

struct ScanRegisterView: View {
    @StateObject private var viewModel: ScanRegisterViewModel
    @StateObject private var camera = CameraCaptureController()
    @Environment(\.dismiss) private var dismiss
    private let onFinished: () -> Void
    /// 買う前チェックと同じ、スキャン確定時のフィードバック（枠を光らせる＋触感）。
    @State private var scanFlashOpacity: Double = 0

    init(bookRepository: BookRepository, onFinished: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ScanRegisterViewModel(bookRepository: bookRepository))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                cameraSection
                resultSection
                Spacer()
            }
            .padding()
            .navigationTitle("本棚に登録")
            .safeAreaInset(edge: .bottom) {
                scannedBookFooter
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                camera.onFrame = { [weak viewModel] buffer in
                    Task { @MainActor in viewModel?.handleCapturedFrame(buffer) }
                }
                camera.start()
            }
            .onDisappear {
                camera.stop()
                onFinished()
            }
            .onChange(of: viewModel.registerState) { _, newValue in
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
        switch viewModel.registerState {
        case .scanning:
            Text("所持している本のバーコードにカメラをかざしてください")
                .foregroundStyle(.secondary)
        case .registering:
            HStack(spacing: 8) {
                ProgressView()
                Text("登録中…").foregroundStyle(.secondary)
            }
        case .error(let message):
            Text(message).foregroundStyle(.red)
        case .result(let result):
            resultCard(for: result)
        }
    }

    @ViewBuilder
    private func resultCard(for result: ScanRegisterViewModel.RegisterResult) -> some View {
        switch result {
        case .registered:
            resultCardView(title: "本棚に登録しました", tint: .green, systemImage: "checkmark.circle.fill")
        case .upgradedFromWishlist:
            resultCardView(title: "気になるリストから購入済みへ更新しました", tint: .green, systemImage: "checkmark.circle.fill")
        case .alreadyOwned:
            resultCardView(title: "既に登録済みです", tint: .secondary, systemImage: "info.circle")
        }
    }

    private func resultCardView(title: String, tint: Color, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(title).font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - スキャンした本（画面下部）

    @ViewBuilder
    private var scannedBookFooter: some View {
        if let book = scannedBook {
            HStack(spacing: 12) {
                coverThumbnail(url: book.coverImageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text("スキャンした本").font(.caption).foregroundStyle(.secondary)
                    Text(book.title).font(.subheadline).fontWeight(.semibold).lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .background(.thinMaterial)
        }
    }

    private var scannedBook: Book? {
        guard case .result(let result) = viewModel.registerState else { return nil }
        switch result {
        case .registered(let book), .upgradedFromWishlist(let book), .alreadyOwned(let book):
            return book
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
