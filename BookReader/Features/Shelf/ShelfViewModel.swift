import Foundation

/// 本棚（F-04積読リスト + F-05気になる本棚 統合画面）。
/// 「気になる本またはシリーズ」を一覧化し、未購入/未読/読書中/読了のステータスを
/// 一目で分かるように表示する。ステータス変更はStatusPillMenuにより2タップで完了する。
@MainActor
final class ShelfViewModel: ObservableObject {
    @Published private(set) var seriesCards: [SeriesProgress] = []
    @Published private(set) var standaloneBooks: [Book] = []
    @Published var errorMessage: String?

    static let overdueThresholdDays = NotificationService.reminderThresholdDays

    private let bookRepository: BookRepository
    private let calculator: SeriesProgressCalculating
    private let affiliateLinkService: AffiliateLinking
    private let volumeCountRefreshService: SeriesVolumeCountRefreshing

    init(
        bookRepository: BookRepository,
        calculator: SeriesProgressCalculating,
        affiliateLinkService: AffiliateLinking = AffiliateLinkService(),
        volumeCountRefreshService: SeriesVolumeCountRefreshing? = nil
    ) {
        self.bookRepository = bookRepository
        self.calculator = calculator
        self.affiliateLinkService = affiliateLinkService
        self.volumeCountRefreshService = volumeCountRefreshService ?? SeriesVolumeCountRefreshService(
            bookRepository: bookRepository,
            calculator: calculator,
            metadataCache: CoreDataSeriesMetadataCache(context: PersistenceController.shared.container.viewContext),
            metadataService: CompositeBookMetadataService()
        )
    }

    /// テストからバックグラウンド再チェックの完了を待ち合わせるために公開している（本番コードからは未使用）。
    private(set) var staleSeriesRefreshTask: Task<Void, Never>?

    func onAppear() {
        reload()
        // 本棚を開くたびに、再チェックが必要なシリーズ（既刊数「不明」または30日以上前に
        // 取得したもの）だけを静かに再取得する。1冊ずつスキャンして登録していく使い方では、
        // シリーズの一部しか登録されていないタイミングでたまたま既刊数が「不明」になることが
        // あるため、残りの巻を登録し終えて本棚を見返した時に自動で回復させるためのもの。
        // 対象が無ければ通信は発生しないため、画面表示のたびに呼んでも負荷は小さい。
        staleSeriesRefreshTask = Task { await refreshStaleSeriesQuietly() }
    }

    /// 本棚画面のpull-to-refresh用。キャッシュの鮮度（最大30日）を待たずに全シリーズの
    /// 既刊数を再取得する。「不明」等の古い結果がキャッシュされたままになっている場合の
    /// 手動リカバリ手段として提供する。
    func refreshSeriesVolumeCounts() async {
        await volumeCountRefreshService.refreshAllSeries()
        reload()
    }

    private func refreshStaleSeriesQuietly() async {
        await volumeCountRefreshService.refreshStaleSeries()
        reload()
    }

    func reload() {
        do {
            seriesCards = try calculator.calculateAll()
            standaloneBooks = try calculator.standaloneBooks()
        } catch {
            errorMessage = "読み込みに失敗しました"
        }
    }

    /// ステータス変更（2タップ操作の実処理）。既存のtitle/seriesName/volumeNumberは変更しない。
    func changeStatus(bookID: UUID, to newStatus: UnifiedStatus) {
        guard let book = try? bookRepository.find(id: bookID) else { return }
        let pair = newStatus.bookStatusPair
        do {
            try bookRepository.update(
                id: bookID,
                changes: BookChanges(
                    title: book.title,
                    seriesName: book.seriesName,
                    volumeNumber: book.volumeNumber,
                    isbn: book.isbn,
                    coverImageURL: book.coverImageURL,
                    status: pair.status,
                    readStatus: pair.readStatus
                )
            )
            reload()
        } catch {
            errorMessage = "保存に失敗しました。もう一度お試しください"
        }
    }

    func elapsedDays(for book: Book) -> Int {
        book.elapsedDays()
    }

    func isOverdue(_ book: Book) -> Bool {
        elapsedDays(for: book) >= Self.overdueThresholdDays
    }

    /// series.nextVolumeISBNが存在する（F-02で当該巻を明示的にスキャン済み）場合はISBN検索、
    /// 存在しない（純粋な自動提案）場合はキーワード検索にフォールバックする。
    func openStoreSearch(for series: SeriesProgress) -> URL {
        if let isbn = series.nextVolumeISBN {
            return affiliateLinkService.amazonSearchURL(isbn: isbn)
        }
        let volume = series.nextVolumeToBuy ?? 1
        return affiliateLinkService.amazonSearchURL(keywords: "\(series.seriesName) \(volume)巻")
    }

    /// 単発の本用。ISBNが分かっていればそのまま検索する。
    func openStoreSearch(for book: Book) -> URL {
        if let isbn = book.isbn {
            return affiliateLinkService.amazonSearchURL(isbn: isbn)
        }
        return affiliateLinkService.amazonSearchURL(keywords: book.title)
    }
}
