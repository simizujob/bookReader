import Foundation

/// タイトルだけで買う前チェックしたい場合の検索（Amazonを開いていなくても使える入り口）。
/// NDLは表紙画像を提供しないため、著者名を添えて候補を見分けられるようにする。
@MainActor
final class TitleSearchViewModel: ObservableObject {
    @Published private(set) var candidates: [TitleSearchCandidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false

    private let titleSearching: TitleSearching

    /// テストから検索の非同期完了を待ち合わせるために公開している（本番コードからは未使用）。
    private(set) var searchTask: Task<Void, Never>?

    init(titleSearching: TitleSearching = NDLSearchService()) {
        self.titleSearching = titleSearching
    }

    func search(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask = Task {
            isSearching = true
            candidates = await titleSearching.searchCandidates(title: trimmed)
            hasSearched = true
            isSearching = false
        }
    }
}
