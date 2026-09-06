import XCTest
@testable import BookReader

final class GoogleBooksServiceTests: XCTestCase {
    private func makeService(json: String) -> GoogleBooksService {
        StubURLProtocol.responseProvider = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (json.data(using: .utf8)!, response)
        }
        return GoogleBooksService(session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.responseProvider = nil
        super.tearDown()
    }

    func test_searchCandidates_returnsTitleAuthorAndCover() async throws {
        let json = """
        {
          "items": [
            {
              "volumeInfo": {
                "title": "鬼滅の刃 1",
                "authors": ["吾峠呼世晴"],
                "industryIdentifiers": [
                  {"type": "ISBN_10", "identifier": "4088801951"},
                  {"type": "ISBN_13", "identifier": "9784088801955"}
                ],
                "imageLinks": {"thumbnail": "http://books.google.com/books/content?id=abc&img=1"}
              }
            }
          ]
        }
        """
        let service = makeService(json: json)

        let candidates = await service.searchCandidates(title: "鬼滅の刃")

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.isbn, "9784088801955", "ISBN_13があればそちらを優先すること")
        XCTAssertEqual(candidates.first?.title, "鬼滅の刃 1")
        XCTAssertEqual(candidates.first?.creator, "吾峠呼世晴")
        XCTAssertEqual(
            candidates.first?.coverImageURL, "https://books.google.com/books/content?id=abc&img=1",
            "ATSでブロックされないようhttp://はhttps://に変換すること"
        )
    }

    func test_searchCandidates_onlyISBN10_convertsToISBN13() async throws {
        // 0306406152は既知の妥当なISBN-10チェックディジット。ISBN-13は9780306406157になる。
        let json = """
        {
          "items": [
            {"volumeInfo": {"title": "テスト本", "industryIdentifiers": [{"type": "ISBN_10", "identifier": "0306406152"}]}}
          ]
        }
        """
        let service = makeService(json: json)

        let candidates = await service.searchCandidates(title: "テスト本")

        XCTAssertEqual(candidates.first?.isbn, "9780306406157")
    }

    func test_searchCandidates_noISBN_isExcluded() async throws {
        let json = """
        {
          "items": [
            {"volumeInfo": {"title": "ISBN無しの本"}}
          ]
        }
        """
        let service = makeService(json: json)

        let candidates = await service.searchCandidates(title: "ISBN無しの本")

        XCTAssertTrue(candidates.isEmpty)
    }

    func test_searchCandidates_deduplicatesByISBN() async throws {
        let json = """
        {
          "items": [
            {"volumeInfo": {"title": "三体", "industryIdentifiers": [{"type": "ISBN_13", "identifier": "9784041061059"}]}},
            {"volumeInfo": {"title": "三体（重複）", "industryIdentifiers": [{"type": "ISBN_13", "identifier": "9784041061059"}]}}
          ]
        }
        """
        let service = makeService(json: json)

        let candidates = await service.searchCandidates(title: "三体")

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.title, "三体")
    }

    func test_searchCandidates_noItems_returnsEmpty() async throws {
        let service = makeService(json: "{}")

        let candidates = await service.searchCandidates(title: "存在しない本")

        XCTAssertTrue(candidates.isEmpty)
    }
}
