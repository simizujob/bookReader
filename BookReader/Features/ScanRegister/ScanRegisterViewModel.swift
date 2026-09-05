import Foundation
import CoreVideo
import CoreImage
import UIKit

/// 本棚に登録（F-01）。詳細設計書5.2参照。
@MainActor
final class ScanRegisterViewModel: ObservableObject {
    struct DetectedBookCandidate: Identifiable, Equatable {
        let id = UUID()
        var isbn: String?
        var ocrTitle: String?
        var thumbnail: UIImage?
        var isDuplicate: Bool
    }

    @Published private(set) var detectedItems: [DetectedBookCandidate] = []
    @Published private(set) var isRegistering = false
    @Published var showManualSearch = false

    private let barcodeScanService: BarcodeScanning
    private let ocrService: SpineTextRecognizing
    private let bookRepository: BookRepository
    private let metadataService: BookMetadataFetching
    private let ciContext = CIContext()

    init(
        barcodeScanService: BarcodeScanning = BarcodeScanService(),
        ocrService: SpineTextRecognizing = SpineOCRService(),
        bookRepository: BookRepository,
        metadataService: BookMetadataFetching = CompositeBookMetadataService()
    ) {
        self.barcodeScanService = barcodeScanService
        self.ocrService = ocrService
        self.bookRepository = bookRepository
        self.metadataService = metadataService
    }

    /// カメラのライブフレームを検出候補に追加する。既に検出済みのISBNは重複追加しない。
    func handleCapturedFrame(_ pixelBuffer: CVPixelBuffer) {
        let thumbnail = makeThumbnail(from: pixelBuffer)

        if let isbn = try? barcodeScanService.detectISBN(in: pixelBuffer) {
            guard !detectedItems.contains(where: { $0.isbn == isbn }) else { return }
            let isDuplicate = (try? bookRepository.isDuplicate(isbn: isbn, title: "")) ?? false
            detectedItems.append(DetectedBookCandidate(isbn: isbn, ocrTitle: nil, thumbnail: thumbnail, isDuplicate: isDuplicate))
            return
        }

        guard let cgImage = makeCGImage(from: pixelBuffer),
              let ocrResult = try? ocrService.recognizeTitle(in: cgImage),
              ocrResult.confidence >= SpineOCRService.confidenceThreshold,
              !ocrResult.text.isEmpty
        else { return }

        guard !detectedItems.contains(where: { $0.ocrTitle == ocrResult.text }) else { return }
        let isDuplicate = (try? bookRepository.isDuplicate(isbn: nil, title: ocrResult.text)) ?? false
        detectedItems.append(DetectedBookCandidate(isbn: nil, ocrTitle: ocrResult.text, thumbnail: thumbnail, isDuplicate: isDuplicate))
    }

    func removeCandidate(_ candidate: DetectedBookCandidate) {
        detectedItems.removeAll { $0.id == candidate.id }
    }

    /// 検出した候補をまとめて登録する（詳細設計書5.2）。
    /// OCR抽出タイトル、またはバーコード経由でOpen Libraryから即時取得できたタイトルは
    /// TitleParserを通してtitle/seriesName/volumeNumberに分解する。
    /// バーコードのみでオフライン登録した場合はseriesName/volumeNumberともnilのまま登録し、
    /// MetadataBackfillServiceによる事後解決に委ねる。
    func confirmRegistration() async {
        isRegistering = true
        defer { isRegistering = false }

        var drafts: [BookDraft] = []
        for candidate in detectedItems where !candidate.isDuplicate {
            if let ocrTitle = candidate.ocrTitle {
                let parsed = TitleParser.parse(ocrTitle)
                drafts.append(BookDraft(
                    isbn: nil,
                    title: parsed.title,
                    seriesName: parsed.seriesName,
                    volumeNumber: parsed.volumeNumber,
                    coverImageURL: nil,
                    status: .owned,
                    readStatus: .unread,
                    metadataFetched: true
                ))
            } else if let isbn = candidate.isbn {
                if let meta = try? await metadataService.fetchMetadata(isbn: isbn) {
                    let resolved = meta.resolvedSeriesInfo
                    drafts.append(BookDraft(
                        isbn: isbn,
                        title: meta.title,
                        seriesName: resolved.seriesName,
                        volumeNumber: resolved.volumeNumber,
                        coverImageURL: meta.coverImageURL,
                        status: .owned,
                        readStatus: .unread,
                        metadataFetched: true
                    ))
                } else {
                    drafts.append(BookDraft(
                        isbn: isbn,
                        title: "ISBN: \(isbn)",
                        seriesName: nil,
                        volumeNumber: nil,
                        coverImageURL: nil,
                        status: .owned,
                        readStatus: .unread,
                        metadataFetched: false
                    ))
                }
            }
        }

        _ = try? bookRepository.insertBatch(drafts)
        detectedItems.removeAll()
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private func makeThumbnail(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        guard let cgImage = makeCGImage(from: pixelBuffer) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
