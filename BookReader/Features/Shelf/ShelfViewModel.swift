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

    init(
        bookRepository: BookRepository,
        calculator: SeriesProgressCalculating,
        affiliateLinkService: AffiliateLinking = AffiliateLinkService()
    ) {
        self.bookRepository = bookRepository
        self.calculator = calculator
        self.affiliateLinkService = affiliateLinkService
    }

    func onAppear() {
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
