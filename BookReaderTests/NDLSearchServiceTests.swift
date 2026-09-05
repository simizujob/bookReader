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

    // MARK: - fetchSeriesVolumeCount（「欠番なしの場合のみ採用」ルール）

    private func makeSeriesSearchXML(items: [(title: String, volume: String?)]) -> String {
        let itemsXML = items.map { item in
            let volumeTag = item.volume.map { "<dcndl:volume>\($0)</dcndl:volume>" } ?? ""
            return "<item><dc:title>\(item.title)</dc:title>\(volumeTag)</item>"
        }.joined()
        return """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>\(itemsXML)</channel>
        </rss>
        """
    }

    func test_fetchSeriesVolumeCount_noGaps_returnsMaxVolume() async throws {
        // 実際に確認した鬼滅の刃（1〜23巻、欠番なし）のケースを模したデータ
        let items = (1...23).map { (title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(count, 23)
    }

    func test_fetchSeriesVolumeCount_hasGaps_returnsNilRatherThanWrongNumber() async throws {
        // 実際に確認した「著者名フィルタなし」のケース（1,10〜17巻しか取れず、2〜9,18〜23が歯抜け）を模したデータ。
        // 誤った既刊数（17）を自信ありげに返すより「不明」の方が安全という方針の検証。
        let items = ([1] + Array(10...17)).map { (title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertNil(count, "歯抜けがある場合は誤った数値を返さずnilにすること")
    }

    func test_fetchSeriesVolumeCount_ignoresNonNumericVolumeFormats() async throws {
        // 実際に確認したONE PIECEのケース（「巻1」「巻90」のような「巻」+数字形式）を模したデータ。
        // ベストエフォート方針では数字のみの表記だけを対象とするため、これらは無視されnilになる。
        let items = [
            (title: "ONE PIECE", volume: "巻1"),
            (title: "ONE PIECE", volume: "巻2"),
            (title: "ONE PIECE", volume: "巻3")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")
        XCTAssertNil(count)
    }

    func test_fetchSeriesVolumeCount_ignoresItemsWithDifferentTitle() async throws {
        var items = (1...5).map { (title: "鬼滅の刃", volume: String($0)) }
        items.append((title: "鬼滅の刃イラスト集", volume: "10")) // タイトル完全一致しない関連グッズ等
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(count, 5, "タイトルが完全一致しない項目（関連グッズ等）は既刊数の計算に含めないこと")
    }

    func test_fetchSeriesVolumeCount_noMatchingItems_returnsNil() async throws {
        let service = makeService(xml: makeSeriesSearchXML(items: []))
        let count = try await service.fetchSeriesVolumeCount(seriesName: "存在しないシリーズ")
        XCTAssertNil(count)
    }
}
