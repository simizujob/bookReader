import XCTest
@testable import BookReader

final class MockTitleSearching: TitleSearching {
    var candidatesByTitle: [String: [TitleSearchCandidate]] = [:]
    private(set) var searchedTitles: [String] = []

    func searchCandidates(title: String) async -> [TitleSearchCandidate] {
        searchedTitles.append(title)
        return candidatesByTitle[title] ?? []
    }
}

@MainActor
final class TitleSearchViewModelTests: XCTestCase {
    func test_search_populatesCandidates() async throws {
        let titleSearching = MockTitleSearching()
        titleSearching.candidatesByTitle["鬼滅の刃"] = [
            TitleSearchCandidate(isbn: "9784088801955", title: "鬼滅の刃 1", creator: "吾峠, 呼世晴")
        ]
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("鬼滅の刃")
        await viewModel.searchTask?.value

        XCTAssertEqual(viewModel.candidates.count, 1)
        XCTAssertEqual(viewModel.candidates.first?.isbn, "9784088801955")
        XCTAssertTrue(viewModel.hasSearched)
    }

    func test_search_trimsWhitespace() async throws {
        let titleSearching = MockTitleSearching()
        titleSearching.candidatesByTitle["三体"] = [
            TitleSearchCandidate(isbn: "9784041061059", title: "三体", creator: nil)
        ]
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("  三体  ")
        await viewModel.searchTask?.value

        XCTAssertEqual(titleSearching.searchedTitles, ["三体"])
        XCTAssertEqual(viewModel.candidates.count, 1)
    }

    func test_search_emptyText_doesNothing() {
        let titleSearching = MockTitleSearching()
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("   ")

        XCTAssertTrue(titleSearching.searchedTitles.isEmpty)
        XCTAssertNil(viewModel.searchTask)
    }

    func test_search_noMatches_setsHasSearchedWithEmptyCandidates() async throws {
        let titleSearching = MockTitleSearching()
        let viewModel = TitleSearchViewModel(titleSearching: titleSearching)

        viewModel.search("存在しない本")
        await viewModel.searchTask?.value

        XCTAssertTrue(viewModel.candidates.isEmpty)
        XCTAssertTrue(viewModel.hasSearched)
    }
}
