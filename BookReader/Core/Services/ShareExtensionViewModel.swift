import Foundation
import os.log

private let logger = Logger(subsystem: "simizuatusi.com.BookReader.ShareExtension", category: "ShareExtensionViewModel")

/// 共有シート版「買う前チェック」。Amazon商品ページのURLを受け取り、ASIN→ISBN変換のうえ
/// カメラ版のPreCheckViewModelと同じjudge()経路で所持状況を判定する。
/// Core/に置くことで、共有シート拡張（BookReaderShareExtension）とアプリ本体の両方から
/// 同じソースを利用しつつ、ユニットテストは通常のBookReaderTestsから実行できるようにしている。
@MainActor
final class ShareExtensionViewModel: ObservableObject {
    enum State: Equatable {
        case loadingURL
        /// Amazonの商品ページと認識できなかった（検索結果ページ、書籍以外の商品等）
        case unrecognized
        case judged(JudgeResult)
        case error(String)
    }

    @Published private(set) var state: State = .loadingURL
    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var title: String?
    @Published private(set) var coverImageURL: String?

    private var seriesName: String?
    private var volumeNumber: Int?
    private var isResolvedFromAPI = false
    private var isbn: String?
    private var asin: String?

    private let bookRepository: BookRepository
    private let metadataService: BookMetadataFetching
    private let affiliateLinkService: AffiliateLinking
    private let paperEditionSearching: PaperEditionSearching

    /// テストからメタデータ取得・紙の本再検索の非同期完了を待ち合わせるために公開している
    /// （本番コードからは未使用）。
    private(set) var enrichmentTask: Task<Void, Never>?
    private(set) var handleTask: Task<Void, Never>?

    init(
        bookRepository: BookRepository,
        metadataService: BookMetadataFetching = CompositeBookMetadataService(),
        affiliateLinkService: AffiliateLinking = AffiliateLinkService(),
        paperEditionSearching: PaperEditionSearching = NDLSearchService()
    ) {
        self.bookRepository = bookRepository
        self.metadataService = metadataService
        self.affiliateLinkService = affiliateLinkService
        self.paperEditionSearching = paperEditionSearching
    }

    /// タグ付きでAmazonの同じ商品ページへ戻るためのURL。ASINを認識できなかった場合はnil。
    var amazonReturnURL: URL? {
        asin.map(affiliateLinkService.amazonProductURL(asin:))
    }

    func handle(sharedURL: URL?) {
        handleTask = Task { await handleAsync(sharedURL: sharedURL) }
    }

    private func handleAsync(sharedURL: URL?) async {
        let extractedASIN = sharedURL.flatMap(AmazonURLParser.extractASIN(from:))
        var resolvedISBN = extractedASIN.flatMap(ISBNConverter.isbn13(fromASIN:))

        // Kindle版等、ASINがISBNとして無効な場合、URLから推測したタイトルで紙の本を
        // 再検索する（ベストエフォート）。それでも見つからなければ.unrecognizedとし、
        // 「紙の商品ページを共有してください」等の案内を表示側に委ねる。
        if resolvedISBN == nil, let sharedURL, let titleHint = AmazonURLParser.extractTitleHint(from: sharedURL) {
            resolvedISBN = await paperEditionSearching.searchPaperEditionISBN(titleHint: titleHint)
        }

        logger.notice("""
        handle(sharedURL:) url=\(sharedURL?.absoluteString ?? "nil", privacy: .public) \
        asin=\(extractedASIN ?? "nil", privacy: .public) \
        isbn=\(resolvedISBN ?? "nil", privacy: .public)
        """)

        guard let asin = extractedASIN, let isbn = resolvedISBN else {
            state = .unrecognized
            return
        }
        self.asin = asin
        self.isbn = isbn

        guard let result = try? bookRepository.judge(isbn: isbn) else {
            state = .error("判定に失敗しました")
            return
        }
        state = .judged(result)

        if case .notOwned = result {
            title = "ISBN: \(isbn)"
            enrichmentTask = Task { await enrichMetadata(isbn: isbn) }
        }
    }

    func addToWishlist() {
        guard case .judged(.notOwned) = state, let isbn else { return }
        WishlistRegistrar.register(
            WishlistRegistrar.Entry(
                isbn: isbn,
                title: title ?? "ISBN: \(isbn)",
                seriesName: seriesName,
                volumeNumber: volumeNumber,
                coverImageURL: coverImageURL,
                metadataFetched: isResolvedFromAPI
            ),
            bookRepository: bookRepository
        )
    }

    private func enrichMetadata(isbn: String) async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        guard let meta = try? await metadataService.fetchMetadata(isbn: isbn) else { return }
        guard self.isbn == isbn else { return } // 別のURLを処理していたら結果を捨てる

        let resolved = meta.resolvedSeriesInfo
        title = meta.title
        coverImageURL = meta.coverImageURL
        seriesName = resolved.seriesName
        volumeNumber = resolved.volumeNumber
        isResolvedFromAPI = true
    }
}
