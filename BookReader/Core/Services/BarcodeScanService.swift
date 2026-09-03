import Foundation
import Vision

protocol BarcodeScanning {
    func detectISBN(in pixelBuffer: CVPixelBuffer) throws -> String?
}

/// バーコード検出（F-01/F-02）。詳細設計書4.4参照。
/// ISBN-13（プレフィックス978/979）のみを判定対象とし、価格表示用JANバーコード等は無視する。
struct BarcodeScanService: BarcodeScanning {
    static func isValidISBN13(_ value: String) -> Bool {
        value.range(of: #"^97[89]\d{10}$"#, options: .regularExpression) != nil
    }

    func detectISBN(in pixelBuffer: CVPixelBuffer) throws -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        guard let results = request.results else { return nil }
        for observation in results {
            if let payload = observation.payloadStringValue, Self.isValidISBN13(payload) {
                return payload
            }
        }
        return nil
    }
}
