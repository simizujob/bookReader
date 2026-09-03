import Foundation

/// 気になる本棚（F-05）。詳細設計書5.4・4.9参照。
@MainActor
final class WishShelfViewModel: ObservableObject {
    @Published private(set) var seriesCards: [SeriesProgress] = []
    /// シリーズ名が未確定のまま「気になるリストへ」で追加された単発の本
    /// （買う前チェックからの登録直後はseriesName未確定のことが多い）。
    @Published private(set) var standaloneBooks: [Book] = []
    @Published var errorMessage: String?

    private let calculator: SeriesProgressCalculating
    private let affiliateLinkService: AffiliateLinking

    init(calculator: SeriesProgressCalculating, affiliateLinkService: AffiliateLinking = AffiliateLinkService()) {
        self.calculator = calculator
        self.affiliateLinkService = affiliateLinkService
    }

    func onAppear() {
        reload()
    }

    func reload() {
        do {
            seriesCards = try calculator.calculateAll()
            standaloneBooks = try calculator.standaloneWishlistBooks()
        } catch {
            errorMessage = "読み込みに失敗しました"
        }
    }

    /// series.nextVolumeISBNが存在する（F-02で当該巻を明示的にスキャン済み）場合はISBN検索、
    /// 存在しない（純粋な自動提案）場合はキーワード検索にフォールバックする（詳細設計書4.9）。
    func openStoreSearch(for series: SeriesProgress) -> URL {
        if let isbn = series.nextVolumeISBN {
            return affiliateLinkService.amazonSearchURL(isbn: isbn)
        }
        let volume = series.nextVolumeToBuy ?? 1
        return affiliateLinkService.amazonSearchURL(keywords: "\(series.seriesName) \(volume)巻")
    }

    /// 単発の気になる本用。ISBNが分かっているのでそのまま検索する。
    func openStoreSearch(for book: Book) -> URL {
        if let isbn = book.isbn {
            return affiliateLinkService.amazonSearchURL(isbn: isbn)
        }
        return affiliateLinkService.amazonSearchURL(keywords: book.title)
    }
}
