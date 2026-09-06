import Foundation

/// タイトルだけで買う前チェックしたい場合の検索（Amazonを開いていなくても使える入り口）。
/// NDL Searchで検索する（Google Books APIも試したが、日本の漫画データの大半がISBNを
/// 持たず判定に使えないことが実データで判明したため戻した。詳細はNDLSearchService参照）。
@MainActor
final class TitleSearchViewModel: ObservableObject {
    @Published private(set) var candidates: [TitleSearchCandidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    /// 通信エラーで検索できなかった場合true。「本当に0件」と区別してユーザーに伝えるため。
    @Published private(set) var searchFailed = false

    private let titleSearching: TitleSearching

    /// テストから検索の非同期完了を待ち合わせるために公開している（本番コードからは未使用）。
    private(set) var searchTask: Task<Void, Never>?

    init(titleSearching: TitleSearching = NDLSearchService()) {
        self.titleSearching = titleSearching
    }

    func search(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reset()
            return
        }
        searchTask = Task {
            isSearching = true
            searchFailed = false
            do {
                candidates = try await titleSearching.searchCandidates(title: trimmed)
            } catch {
                candidates = []
                searchFailed = true
            }
            hasSearched = true
            isSearching = false
        }
    }

    /// 検索欄が空になった場合に、検索前の状態（案内文表示）へ戻す。
    func reset() {
        searchTask?.cancel()
        searchTask = nil
        candidates = []
        hasSearched = false
        searchFailed = false
        isSearching = false
    }
}
