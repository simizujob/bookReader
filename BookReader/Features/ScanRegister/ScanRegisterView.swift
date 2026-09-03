import SwiftUI

struct ScanRegisterView: View {
    @StateObject private var viewModel: ScanRegisterViewModel
    @StateObject private var camera = CameraCaptureController()
    @Environment(\.dismiss) private var dismiss
    private let onFinished: () -> Void

    init(bookRepository: BookRepository, onFinished: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ScanRegisterViewModel(bookRepository: bookRepository))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                cameraSection
                Text("\(viewModel.detectedItems.count)冊 検出中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                candidateList
                Button {
                    Task {
                        await viewModel.confirmRegistration()
                        onFinished()
                        dismiss()
                    }
                } label: {
                    if viewModel.isRegistering {
                        ProgressView()
                    } else {
                        Text("この\(viewModel.detectedItems.count)冊を登録する")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.detectedItems.isEmpty || viewModel.isRegistering)
            }
            .padding()
            .navigationTitle("本棚に登録")
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
            .onDisappear { camera.stop() }
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.black)
            if camera.isCameraAvailable {
                CameraPreviewView(session: camera.captureSession)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("カメラを利用できません").foregroundStyle(.white)
            }
        }
        .frame(height: 240)
    }

    private var candidateList: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.detectedItems) { candidate in
                    VStack(spacing: 4) {
                        Image(uiImage: candidate.thumbnail ?? UIImage())
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                if candidate.isDuplicate {
                                    RoundedRectangle(cornerRadius: 6).stroke(Color.orange, lineWidth: 2)
                                }
                            }
                        if candidate.isDuplicate {
                            Text("登録済み").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .onTapGesture { viewModel.removeCandidate(candidate) }
                }
            }
        }
        .frame(height: 80)
    }
}
