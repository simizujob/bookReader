import SwiftUI

struct PreCheckView: View {
    @StateObject private var viewModel: PreCheckViewModel
    @StateObject private var camera = CameraCaptureController()

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
            .onAppear {
                camera.onFrame = { [weak viewModel] buffer in
                    Task { @MainActor in viewModel?.handleCapturedFrame(buffer) }
                }
                camera.start()
            }
            .onDisappear { camera.stop() }
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
            Text(message).foregroundStyle(.red)
        case .judged(.owned):
            resultCard(
                title: "持っています",
                subtitle: nil,
                tint: .green,
                systemImage: "checkmark.circle.fill"
            )
        case .judged(.notOwned):
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
                    subtitle: viewModel.enrichedContext.title,
                    tint: .secondary,
                    systemImage: "xmark.circle"
                )
            }

            if let warning = viewModel.enrichedContext.editionWarning {
                Text("同じタイトルの別版を登録済みかもしれません（類似度\(Int(warning.similarity * 100))%）")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("気になるリストへ") {
                viewModel.addCurrentResultToWishlist()
            }
            .buttonStyle(.borderedProminent)
        }
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
}
