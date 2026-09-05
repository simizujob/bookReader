import XCTest
@testable import BookReader

final class NDLSearchServiceTests: XCTestCase {
    /// 実際にNDL Searchから取得した応答（2026-09-05時点、ISBN 9784081135684 = HUNTER×HUNTER 5巻）を
    /// 固定データとして使用する。このISBNはOpen Library・openBDどちらにも存在しない（curlで確認済み）が、
    /// 国立国会図書館サーチには存在することを確認済み。dcndl:volumeで巻数が構造化取得できる実例。
    private static let foundResponseXML = """
    <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:openSearch="http://a9.com/-/spec/opensearchrss/1.0/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
      <channel>
        <title>9784081135684 - 国立国会図書館サーチ OpenSearch</title>
        <openSearch:totalResults>1</openSearch:totalResults>
        <item>
          <title>Hunter×hunter</title>
          <link>https://ndlsearch.ndl.go.jp/books/R100000002-I029458675</link>
          <description><![CDATA[<p>5,集英社,2016,978-4-08-113568-4<p><ul><li>タイトル：Hunter×hunter</li></ul>]]></description>
          <author>富樫, 義博, 1966-,冨樫義博 著</author>
          <pubDate>Mon, 31 Jan 2022 18:28:48 +0900</pubDate>
          <dc:title>Hunter×hunter</dc:title>
          <dc:creator>富樫, 義博, 1966-</dc:creator>
          <dcndl:volume>5</dcndl:volume>
          <dc:publisher>集英社</dc:publisher>
          <dc:identifier xsi:type="dcndl:ISBN" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">978-4-08-113568-4</dc:identifier>
        </item>
      </channel>
    </rss>
    """

    private static let notFoundResponseXML = """
    <rss xmlns:openSearch="http://a9.com/-/spec/opensearchrss/1.0/" version="2.0">
      <channel>
        <title>9780000000000 - 国立国会図書館サーチ OpenSearch</title>
        <openSearch:totalResults>0</openSearch:totalResults>
      </channel>
    </rss>
    """

    private func makeService(xml: String) -> NDLSearchService {
        StubURLProtocol.responseProvider = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (xml.data(using: .utf8)!, response)
        }
        return NDLSearchService(session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.responseProvider = nil
        super.tearDown()
    }

    func test_fetchMetadata_realWorldFoundResponse_parsesTitleAndVolume() async throws {
        let service = makeService(xml: Self.foundResponseXML)
        let metadata = try await service.fetchMetadata(isbn: "9784081135684")

        XCTAssertEqual(metadata.title, "Hunter×hunter 5")
        XCTAssertEqual(metadata.seriesName, "Hunter×hunter")
        XCTAssertEqual(metadata.volumeNumber, 5)
        XCTAssertNil(metadata.coverImageURL, "NDL Searchは表紙画像を提供しない")
    }

    func test_fetchMetadata_notFoundResponse_throwsNotFound() async throws {
        let service = makeService(xml: Self.notFoundResponseXML)
        do {
            _ = try await service.fetchMetadata(isbn: "9780000000000")
            XCTFail("notFoundが投げられるべき")
        } catch let error as NDLSearchError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_fetchMetadata_bookWithoutVolume_returnsNilSeriesInfo() async throws {
        let xml = """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>
            <item>
              <dc:title>三体</dc:title>
            </item>
          </channel>
        </rss>
        """
        let service = makeService(xml: xml)
        let metadata = try await service.fetchMetadata(isbn: "9781111111111")

        XCTAssertEqual(metadata.title, "三体")
        XCTAssertNil(metadata.seriesName)
        XCTAssertNil(metadata.volumeNumber)
    }
}
