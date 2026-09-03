import AVFoundation
import SwiftUI

/// F-01/F-02共通のカメラキャプチャ。詳細設計書4.4「呼び出しは専用DispatchQueue上で実行」に対応。
/// シミュレータ等カメラが存在しない環境ではisCameraAvailableがfalseのまま安全に何もしない。
final class CameraCaptureController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var isCameraAvailable = false

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sampleQueue = DispatchQueue(label: "com.bookreader.camera.sample")
    private var lastProcessedAt = Date.distantPast
    private let minFrameInterval: TimeInterval = 0.4

    var onFrame: ((CVPixelBuffer) -> Void)?

    var captureSession: AVCaptureSession { session }

    func configureIfNeeded() {
        guard session.inputs.isEmpty else { return }
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            isCameraAvailable = false
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
        isCameraAvailable = true
    }

    func start() {
        configureIfNeeded()
        guard isCameraAvailable else { return }
        sampleQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sampleQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedAt) >= minFrameInterval else { return }
        lastProcessedAt = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}

/// AVCaptureVideoPreviewLayerをSwiftUIで表示するためのラッパー。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
