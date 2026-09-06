import Foundation
import CoreVideo

/// 買う前チェック（F-02）。詳細設計書5.1・4.1a参照。
/// judge()はオフラインで確実に返せる所持/気になる登録済み/未登録のみを同期的に扱い、
/// 「シリーズの一部を所持」等の文脈情報は非同期メタデータ取得後にenrichedContextへ反映する。
/// 判定結果を表示中は、ユーザーが明示的に次へ進む操作をするまで新しいISBNの検出を無視する
/// （結果を確認せず次々スキャンされてしまうのを防ぐ仕様）。
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
        var seriesName: String?
        var volumeNumber: Int?
        var editionWarning: FuzzyMatchResult?
        var partialSeriesInfo: PartialSeriesInfo?
        /// trueならtitleはAPI（NDL Search／openBD／Open Libraryのいずれか）から正式に取得できたもの。
        /// falseなら「ISBN: xxx」の仮表示のみ（どのAPIにも当該ISBNの収載がなかった場合）。
        var isResolvedFromAPI = false
    }

    @Published private(set) var scanState: ScanState = .scanning
    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var enrichedContext = EnrichedContext()
    /// AmazonのURL貼り付け経由で判定した場合の戻り先（タグ付き）。カメラでのスキャン経由では
    /// 戻り先が無いためnilのまま。ユーザーが明示的にopenAmazonReturnURL()を呼んだ場合のみ
    /// amazonRedirectURLへ渡り、SafariViewが開く。登録直後に自動で画面遷移すると、連続して
    /// 何冊もチェックしたいユーザーの邪魔になるため、自動遷移はしない仕様にしている。
    @Published private(set) var amazonReturnURL: URL?
    /// ViewはこれをSafariViewの.sheet(item:)で開く。Amazonのアプリへ横取りされずCookieベースの
    /// アフィリエイト計測を確実にするため、SFSafariViewController（Safari自体）で開く。
    @Published var amazonRedirectURL: IdentifiableURL?

    private let barcodeScanService: BarcodeScanning
    private let bookRepository: BookRepository
    private let metadataService: BookMetadataFetching
    private let paperEditionSearching: PaperEditionSearching
    private let affiliateLinkService: AffiliateLinking

    init(
        barcodeScanService: BarcodeScanning = BarcodeScanService(),
        bookRepository: BookRepository,
        metadataService: BookMetadataFetching = CompositeBookMetadataService(),
        paperEditionSearching: PaperEditionSearching = NDLSearchService(),
        affiliateLinkService: AffiliateLinking = AffiliateLinkService()
    ) {
        self.barcodeScanService = barcodeScanService
        self.bookRepository = bookRepository
        self.metadataService = metadataService
        self.paperEditionSearching = paperEditionSearching
        self.affiliateLinkService = affiliateLinkService
    }

    func handleCapturedFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let isbn = try? barcodeScanService.detectISBN(in: pixelBuffer) else { return }
        onISBNDetected(isbn)
    }

    /// テスト・手動検索経由など、ISBNが既に分かっている場合の判定エントリポイント
    func judge(isbn: String) {
        onISBNDetected(isbn)
    }

    /// カメラでの読み取りに加え、AmazonのURLを直接貼り付けても判定できるようにする入り口。
    /// Kindle版等でASINがISBNとして無効な場合は、URLから推測したタイトルで紙の本を再検索する
    /// （共有シート拡張機能のShareExtensionViewModelと同じロジック）。
    private(set) var amazonURLCheckTask: Task<Void, Never>?

    func checkAmazonURL(_ text: String) {
        guard case .scanning = scanState else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let asin = AmazonURLParser.extractASIN(from: url) else {
            scanState = .error("AmazonのURLとして認識できませんでした")
            return
        }

        if let isbn = ISBNConverter.isbn13(fromASIN: asin) {
            amazonReturnURL = affiliateLinkService.amazonProductURL(asin: asin)
            onISBNDetected(isbn)
            return
        }

        amazonURLCheckTask = Task {
            if let titleHint = AmazonURLParser.extractTitleHint(from: url),
               let paperISBN = await paperEditionSearching.searchPaperEditionISBN(titleHint: titleHint) {
                amazonReturnURL = affiliateLinkService.amazonProductURL(asin: asin)
                onISBNDetected(paperISBN)
            } else {
                scanState = .error("Kindle版の場合は紙の本の商品ページのURLを貼り付けてください")
            }
        }
    }

    /// 「Amazonで見る」ボタン等から、ユーザーが明示的にAmazonへ戻りたい場合に呼び出す。
    func openAmazonReturnURL() {
        guard let amazonReturnURL else { return }
        amazonRedirectURL = IdentifiableURL(url: amazonReturnURL)
    }

    /// 未登録の本を気になるリストへ登録し、次のスキャンへ進む。
    func addToWishlistAndContinueScanning() {
        guard case .judged(.notOwned) = scanState, let lastISBN else { return }
        WishlistRegistrar.register(
            WishlistRegistrar.Entry(
                isbn: lastISBN,
                title: enrichedContext.title ?? "ISBN: \(lastISBN)",
                seriesName: enrichedContext.seriesName,
                volumeNumber: enrichedContext.volumeNumber,
                coverImageURL: enrichedContext.coverImageURL,
                metadataFetched: enrichedContext.isResolvedFromAPI
            ),
            bookRepository: bookRepository
        )
        resetForNextScan()
    }

    /// 登録せずに次のスキャンへ進む。
    func skipAndContinueScanning() {
        resetForNextScan()
    }

    /// 既に所持済み／気になるリストに登録済みの場合に、そのまま次のスキャンへ進む。
    func continueScanning() {
        resetForNextScan()
    }

    private var lastISBN: String?
    /// テストからメタデータ取得の非同期完了を待ち合わせるために公開している（本番コードからは未使用）。
    private(set) var enrichmentTask: Task<Void, Never>?

    private func resetForNextScan() {
        enrichmentTask?.cancel()
        enrichmentTask = nil
        amazonURLCheckTask?.cancel()
        amazonURLCheckTask = nil
        lastISBN = nil
        enrichedContext = EnrichedContext()
        scanState = .scanning
        amazonReturnURL = nil
    }

    private func onISBNDetected(_ isbn: String) {
        // 判定結果（またはエラー）を表示中は、次へ進むボタンが押されるまで新しいISBNの検出を
        // 無視する。結果を確認する前に次々スキャンされてしまうのを防ぐための仕様変更。
        guard case .scanning = scanState else { return }

        lastISBN = isbn
        enrichedContext = EnrichedContext()

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

    /// judge()で.notOwnedが返った直後に非同期で呼び出す（詳細設計書5.1参照）。
    /// 画面下部への表示用に、スキャンした本のタイトル・表紙画像もここで補完する。
    private func enrichAfterMetadata(isbn: String) async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        guard let meta = try? await metadataService.fetchMetadata(isbn: isbn) else { return }
        guard lastISBN == isbn else { return } // 別の本をスキャンしていたら結果を捨てる

        let resolved = meta.resolvedSeriesInfo
        var context = EnrichedContext(
            title: meta.title,
            coverImageURL: meta.coverImageURL,
            seriesName: resolved.seriesName,
            volumeNumber: resolved.volumeNumber,
            isResolvedFromAPI: true
        )

        if let edition = try? bookRepository.fuzzyMatch(title: meta.title, excludingISBN: isbn) {
            context.editionWarning = edition
        }

        if let seriesName = resolved.seriesName, let volumeNumber = resolved.volumeNumber {
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
