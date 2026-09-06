import Foundation

/// タイトル検索の主要な情報源（Google Books API）と、失敗時のフォールバック（NDL Search）を
/// 束ねる窓口。App Store公開後は不特定多数のユーザーが同じAPIキー（＝同じ1日あたりの割り当て）を
/// 共有するため、割り当て超過時にタイトル検索そのものが完全に止まってしまわないようにする。
/// 割り当て超過のレスポンスはitemsキーを含まないだけでデコード自体は成功してしまい、
/// 「該当0件」と区別が付かない（実機で確認）ため、主要な情報源が空を返した場合は常に
/// フォールバックを試す（結果的に、Googleで本当に0件だった場合もNDLで再挑戦することになるが、
/// 見つかる可能性が上がるだけで害はない）。
struct CompositeTitleSearchService: TitleSearching {
    private let primary: TitleSearching
    private let fallback: TitleSearching

    init(
        primary: TitleSearching = GoogleBooksService(),
        fallback: TitleSearching = NDLSearchService()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func searchCandidates(title: String) async -> [TitleSearchCandidate] {
        let primaryResults = await primary.searchCandidates(title: title)
        guard primaryResults.isEmpty else { return primaryResults }
        return await fallback.searchCandidates(title: title)
    }
}
