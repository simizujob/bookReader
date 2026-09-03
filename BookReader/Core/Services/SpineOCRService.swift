import Foundation
import Vision
import CoreGraphics

struct OCRResult: Equatable {
    let text: String
    let confidence: Float
    let orientationUsed: CGImagePropertyOrientation.RawValue
}

protocol SpineTextRecognizing {
    func recognizeTitle(in image: CGImage) throws -> OCRResult
}

/// 背表紙OCRフォールバック（F-03）。詳細設計書4.5参照。
/// 和書の背表紙は縦書きが多く、Visionは横書き前提の認識精度が高いため、
/// 3方向の向きヒントで個別に認識処理を実行し、最も信頼度の高い結果を採用する。
/// （画像の物理的な再レンダリングではなく、VNImageRequestHandlerへの向きヒントで実現し、コストを抑える）
struct SpineOCRService: SpineTextRecognizing {
    static let confidenceThreshold: Float = 0.5

    private static let orientationsToTry: [CGImagePropertyOrientation] = [.up, .right, .left]

    func recognizeTitle(in image: CGImage) throws -> OCRResult {
        var best: OCRResult?

        for orientation in Self.orientationsToTry {
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([request])

            guard let candidate = request.results?
                .compactMap({ $0.topCandidates(1).first })
                .max(by: { $0.confidence < $1.confidence })
            else { continue }

            if best == nil || candidate.confidence > best!.confidence {
                best = OCRResult(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    orientationUsed: orientation.rawValue
                )
            }
        }

        return best ?? OCRResult(text: "", confidence: 0, orientationUsed: CGImagePropertyOrientation.up.rawValue)
    }
}
