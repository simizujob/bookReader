import Foundation
import CoreVideo

/// 買う前チェック（F-02）。詳細設計書5.1・4.1a参照。
/// judge()はオフラインで確実に返せる所持/未所持のみを同期的に扱い、
/// 「シリーズの一部を所持」等の文脈情報は非同期メタデータ取得後にenrichedContextへ反映する。
@MainActor
final class PreCheckViewModel: ObservableObject {
    enum ScanState: Equatable {
        case scanning
        case judged(JudgeResult)
        case error(String)
    }

    struct PartialSeriesInfo: Equatable {
        var ownedThrough: Int
        var missingVolume: Int
    }

    struct EnrichedContext: Equatable {
        var title: String?
        var coverImageURL: String?
        var editionWarning: FuzzyMatchResult?
        var partialSeriesInfo: PartialSeriesInfo?
        /// trueならtitleはAPI（openBD優先／Open Libraryフォールバック）から正式に取得できたもの。
        /// falseなら「ISBN: xxx」の仮表示のみ（どちらのAPIにも当該ISBNの収載がなかった場合）。
        var isResolvedFromAPI = false
    }

    @Published private(set) var scanState: ScanState = .scanning
    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var enrichedContext = EnrichedContext()
    @Published private(set) var didAddToWishlist = false
    @Published var showManualSearch = false

    private var consecutiveDetectionFailures = 0
    private let failureThresholdForManualSearch = 5

    private let barcodeScanService: BarcodeScanning
    private let bookRepository: BookRepository
    private let metadataService: BookMetadataFetching

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
        guard let isbn = try? barcodeScanService.detectISBN(in: pixelBuffer) else {
            onDetectionFailed()
            return
        }
        onISBNDetected(isbn)
    }

    /// テスト・手動検索経由など、ISBNが既に分かっている場合の判定エントリポイント
    func judge(isbn: String) {
        onISBNDetected(isbn)
    }

    func addCurrentResultToWishlist() {
        guard case .judged(.notOwned) = scanState, let lastISBN else { return }
        let title = enrichedContext.title ?? "ISBN: \(lastISBN)"
        // APIから正式なタイトルが取れている場合のみ、シリーズ名・巻数を分解して登録する
        // （TitleParserの共通ロジック。F-01/バックフィルと同じ扱い）。
        let parsed = enrichedContext.isResolvedFromAPI ? TitleParser.parse(title) : nil
        guard (try? bookRepository.insert(BookDraft(
            isbn: lastISBN,
            title: title,
            seriesName: parsed?.seriesName,
            volumeNumber: parsed?.volumeNumber,
            coverImageURL: enrichedContext.coverImageURL,
            status: .wishlist,
            readStatus: .unread,
            metadataFetched: enrichedContext.isResolvedFromAPI
        ))) != nil else { return }
        didAddToWishlist = true
    }

    private var lastISBN: String?
    /// テストからメタデータ取得の非同期完了を待ち合わせるために公開している（本番コードからは未使用）。
    private(set) var enrichmentTask: Task<Void, Never>?

    private func onISBNDetected(_ isbn: String) {
        // カメラが同じ本を映し続けている間、0.4秒間隔で同じISBNが繰り返し検出され続ける。
        // 既に同じISBNの判定結果を表示中であれば再処理しない（画面のちらつき・
        // ユーザー操作中の再レンダリングによるタップ取りこぼしを防ぐ）。
        if isbn == lastISBN, case .judged = scanState {
            return
        }

        consecutiveDetectionFailures = 0
        lastISBN = isbn
        enrichedContext = EnrichedContext()
        didAddToWishlist = false

        guard let result = try? bookRepository.judge(isbn: isbn) else {
            scanState = .error("判定に失敗しました")
            return
        }
        scanState = .judged(result)

        if case .notOwned = result {
            // どちらのAPIにもISBN未収載のことがある（特にOpen Libraryは日本の書籍の網羅性が低い）ため、
            // API取得を待たず、まずISBNそのものを仮タイトルとして即時表示する。
            // 取得に成功すればenrichAfterMetadataが正式なタイトル・表紙で上書きする。
            enrichedContext = EnrichedContext(title: "ISBN: \(isbn)")
            enrichmentTask = Task { await enrichAfterMetadata(isbn: isbn) }
        }
    }

    private func onDetectionFailed() {
        consecutiveDetectionFailures += 1
        if consecutiveDetectionFailures >= failureThresholdForManualSearch {
            showManualSearch = true
        }
    }

    /// judge()で.notOwnedが返った直後に非同期で呼び出す（詳細設計書5.1参照）。
    /// 画面下部への表示用に、スキャンした本のタイトル・表紙画像もここで補完する。
    private func enrichAfterMetadata(isbn: String) async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        guard let meta = try? await metadataService.fetchMetadata(isbn: isbn) else { return }
        guard lastISBN == isbn else { return } // 別の本をスキャンしていたら結果を捨てる

        var context = EnrichedContext(title: meta.title, coverImageURL: meta.coverImageURL, isResolvedFromAPI: true)

        if let edition = try? bookRepository.fuzzyMatch(title: meta.title, excludingISBN: isbn) {
            context.editionWarning = edition
        }

        let parsed = TitleParser.parse(meta.title)
        if let seriesName = parsed.seriesName, let volumeNumber = parsed.volumeNumber {
            let seriesKey = SeriesKeyNormalizer.normalize(seriesName)
            let owned = (try? bookRepository.fetchAll())?
                .filter { $0.seriesKey == seriesKey && $0.status == .owned }
                .compactMap { $0.volumeNumber }
                .sorted() ?? []
            if let maxOwned = owned.max() {
                context.partialSeriesInfo = PartialSeriesInfo(ownedThrough: maxOwned, missingVolume: volumeNumber)
            }
        }

        enrichedContext = context
    }
}
