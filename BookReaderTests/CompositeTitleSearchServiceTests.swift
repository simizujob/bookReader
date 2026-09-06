import XCTest
@testable import BookReader

private final class StubTitleSearching: TitleSearching {
    var results: [TitleSearchCandidate] = []
    private(set) var searchedTitles: [String] = []

    func searchCandidates(title: String) async -> [TitleSearchCandidate] {
        searchedTitles.append(title)
        return results
    }
}

final class CompositeTitleSearchServiceTests: XCTestCase {
    /// メイン（Google Books）が候補を返せた場合は、フォールバック（NDL）には問い合わせないこと。
    func test_searchCandidates_primarySucceeds_doesNotCallFallback() async throws {
        let primary = StubTitleSearching()
        primary.results = [TitleSearchCandidate(isbn: "9784088801955", title: "鬼滅の刃 1", creator: nil, coverImageURL: nil)]
        let fallback = StubTitleSearching()
        let service = CompositeTitleSearchService(primary: primary, fallback: fallback)

        let candidates = await service.searchCandidates(title: "鬼滅の刃")

        XCTAssertEqual(candidates.map(\.isbn), ["9784088801955"])
        XCTAssertTrue(fallback.searchedTitles.isEmpty, "メインが成功した場合はフォールバックを呼ばないこと")
    }

    /// 回帰テスト: Google Books APIが割り当て超過等で失敗すると空配列を返すが、これは
    /// 「該当0件」と区別が付かない（実機で確認）。メインが空を返した場合は必ずNDLへ
    /// フォールバックし、タイトル検索そのものが完全に止まらないようにすること。
    func test_searchCandidates_primaryReturnsEmpty_fallsBackToSecondary() async throws {
        let primary = StubTitleSearching() // 空のまま = 割り当て超過や該当0件を模す
        let fallback = StubTitleSearching()
        fallback.results = [TitleSearchCandidate(isbn: "9784041061059", title: "三体", creator: nil, coverImageURL: nil)]
        let service = CompositeTitleSearchService(primary: primary, fallback: fallback)

        let candidates = await service.searchCandidates(title: "三体")

        XCTAssertEqual(candidates.map(\.isbn), ["9784041061059"])
        XCTAssertEqual(fallback.searchedTitles, ["三体"])
    }

    func test_searchCandidates_bothEmpty_returnsEmpty() async throws {
        let service = CompositeTitleSearchService(primary: StubTitleSearching(), fallback: StubTitleSearching())

        let candidates = await service.searchCandidates(title: "存在しない本")

        XCTAssertTrue(candidates.isEmpty)
    }
}
