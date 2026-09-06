import XCTest
@testable import BookReader

final class MockTitleSearching: TitleSearching {
    var candidatesByTitle: [String: [TitleSearchCandidate]] = [:]
    var shouldThrow = false
    private(set) var searchedTitles: [String] = []

    func searchCandidates(title: String) async throws -> [TitleSearchCandidate] {
        searchedTitles.append(title)
        if shouldThrow {
            throw NDLSearchError.network("テスト用のエラー")
        }
        return candidatesByTitle[title] ?? []
    }
}

@MainActor
final class TitleSearchViewModelTests: XCTestCase {
    func test_search_populatesCandidates() async throws {
        let titleSearching = MockTitleSearching()
        titleSearching.candidatesByTitle["鬼滅の刃"] = [
            TitleSearchCandidate(isbn: "9784088801955", title: "鬼滅の刃 1", creator: "吾峠, 呼世晴", volumeLabel: "1巻")
        ]
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("鬼滅の刃")
        await viewModel.searchTask?.value

        XCTAssertEqual(viewModel.candidates.count, 1)
        XCTAssertEqual(viewModel.candidates.first?.isbn, "9784088801955")
        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertFalse(viewModel.searchFailed)
    }

    func test_search_trimsWhitespace() async throws {
        let titleSearching = MockTitleSearching()
        titleSearching.candidatesByTitle["三体"] = [
            TitleSearchCandidate(isbn: "9784041061059", title: "三体", creator: nil, volumeLabel: nil)
        ]
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("  三体  ")
        await viewModel.searchTask?.value

        XCTAssertEqual(titleSearching.searchedTitles, ["三体"])
        XCTAssertEqual(viewModel.candidates.count, 1)
    }

    func test_search_emptyText_resetsWithoutSearching() {
        let titleSearching = MockTitleSearching()
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("   ")

        XCTAssertTrue(titleSearching.searchedTitles.isEmpty)
        XCTAssertNil(viewModel.searchTask)
        XCTAssertFalse(viewModel.hasSearched)
    }

    func test_search_noMatches_setsHasSearchedWithEmptyCandidates() async throws {
        let titleSearching = MockTitleSearching()
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("存在しない本")
        await viewModel.searchTask?.value

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertFalse(viewModel.searchFailed)
    }

    /// 回帰テスト: 通信エラーで検索できなかった場合と「本当に0件」の場合を区別できるようにする
    /// （どちらも同じ「見つかりませんでした」表示になっていた不具合の改善）。
    func test_search_networkFailure_setsSearchFailedWithoutPopulatingCandidates() async throws {
        let titleSearching = MockTitleSearching()
        titleSearching.shouldThrow = true
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("鬼滅の刃")
        await viewModel.searchTask?.value

        XCTAssertTrue(viewModel.searchFailed)
        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.hasSearched)
    }

    func test_reset_clearsSearchState() async throws {
        let titleSearching = MockTitleSearching()
        titleSearching.candidatesByTitle["鬼滅の刃"] = [
            TitleSearchCandidate(isbn: "9784088801955", title: "鬼滅の刃 1", creator: nil, volumeLabel: "1巻")
        ]
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)
        viewModel.search("鬼滅の刃")
        await viewModel.searchTask?.value

        viewModel.reset()

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertFalse(viewModel.searchFailed)
        XCTAssertNil(viewModel.searchTask)
    }
}
