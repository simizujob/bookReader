import Foundation
import CoreVideo

/// 本棚に登録（F-01）。所持済みの本をISBNバーコードでスキャンして登録する。
/// 買う前チェック（PreCheckViewModel）と同じ、バーコード単発検出方式を採用する
/// （背表紙OCRによるタイトル認識は誤検出が多く不安定だったため廃止した）。
/// 既に「気になる本棚」へ登録済みの巻をスキャンした場合は、新規登録せず既存のレコードを
/// 購入済みステータスへ更新する（重複登録の防止）。
@MainActor
final class ScanRegisterViewModel: ObservableObject {
    enum RegisterResult: Equatable {
        /// 新規に購入済みとして登録した
        case registered(Book)
        /// 気になるリスト（ISBN未確定のプレースホルダーを含む）から購入済みへ更新した
        case upgradedFromWishlist(Book)
        /// 既に購入済みとして登録済みだった
        case alreadyOwned(Book)
    }

    enum RegisterState: Equatable {
        case scanning
        case registering
        case result(RegisterResult)
        case error(String)
    }

    @Published private(set) var registerState: RegisterState = .scanning

    private let barcodeScanService: BarcodeScanning
    private let bookRepository: BookRepository
    private let metadataService: BookMetadataFetching

    private var lastISBN: String?
    /// テストから登録処理の非同期完了を待ち合わせるために公開している（本番コードからは未使用）。
    private(set) var registrationTask: Task<Void, Never>?

    init(
        barcodeScanService: BarcodeScanning = BarcodeScanService(),
        bookRepository: BookRepository,
        metadataService: BookMetadataFetching = CompositeBookMetadataService()
    ) {
        self.barcodeScanService = barcodeScanService
        self.bookRepository = bookRepository
        self.metadataService = metadataService
    }

    func handleCapturedFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let isbn = try? barcodeScanService.detectISBN(in: pixelBuffer) else { return }
        registerIfNeeded(isbn: isbn)
    }

    /// テスト・手動検索経由など、ISBNが既に分かっている場合のエントリポイント
    func register(isbn: String) {
        registerIfNeeded(isbn: isbn)
    }

    private func registerIfNeeded(isbn: String) {
        // カメラが同じ本を映し続けている間、同じISBNが繰り返し検出され続けるため、
        // 直前と同じISBNの間は再処理しない。
        guard isbn != lastISBN else { return }
        lastISBN = isbn
        registrationTask = Task { await performRegistration(isbn: isbn) }
    }

    private func performRegistration(isbn: String) async {
        registerState = .registering
        let meta = try? await metadataService.fetchMetadata(isbn: isbn)
        let resolved = meta?.resolvedSeriesInfo
        let title = meta?.title ?? "ISBN: \(isbn)"

        do {
            if let existing = try bookRepository.find(isbn: isbn) {
                if existing.status == .owned {
                    registerState = .result(.alreadyOwned(existing))
                    return
                }
                let updated = try bookRepository.update(
                    id: existing.id,
                    changes: BookChanges(
                        title: title,
                        seriesName: resolved?.seriesName ?? existing.seriesName,
                        volumeNumber: resolved?.volumeNumber ?? existing.volumeNumber,
                        isbn: isbn,
                        coverImageURL: meta?.coverImageURL ?? existing.coverImageURL,
                        status: .owned,
                        readStatus: .unread
                    )
                )
                registerState = .result(.upgradedFromWishlist(updated))
                return
            }

            // 既刊数が判明したシリーズは未登録の巻をISBN未確定のプレースホルダーとして
            // 自動登録している（SeriesVolumeCountRefreshService）。同じ巻を購入してスキャンした
            // 場合、新規登録せずそのプレースホルダーを実データで更新する。
            if let seriesName = resolved?.seriesName,
               let volumeNumber = resolved?.volumeNumber,
               let placeholder = try bookRepository.find(
                   seriesKey: SeriesKeyNormalizer.normalize(seriesName),
                   volumeNumber: volumeNumber
               ),
               placeholder.isbn == nil {
                let updated = try bookRepository.update(
                    id: placeholder.id,
                    changes: BookChanges(
                        title: title,
                        seriesName: seriesName,
                        volumeNumber: volumeNumber,
                        isbn: isbn,
                        coverImageURL: meta?.coverImageURL,
                        status: .owned,
                        readStatus: .unread
                    )
                )
                registerState = .result(.upgradedFromWishlist(updated))
                return
            }

            let inserted = try bookRepository.insert(BookDraft(
                isbn: isbn,
                title: title,
                seriesName: resolved?.seriesName,
                volumeNumber: resolved?.volumeNumber,
                coverImageURL: meta?.coverImageURL,
                status: .owned,
                readStatus: .unread,
                metadataFetched: meta != nil
            ))
            registerState = .result(.registered(inserted))
        } catch {
            registerState = .error("登録に失敗しました")
        }
    }
}
