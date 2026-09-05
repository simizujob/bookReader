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
          <category>図書</category>
          <category>紙</category>
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

    /// 回帰テスト: 実際にNDL Searchで確認した事例（ISBN 9784088725710 = HUNTER×HUNTER 1巻 1998年初版）を
    /// 固定データとして使用する。NDLは同一ISBNに対し、並列タイトル表記（"Hunter×hunter = ハンター ハンター"）
    /// で数字の巻数を持つ旧レコードと、シリーズ内の他の巻と同じ表記だが巻数が"no.1"で数字ではない
    /// レコードの2件を返す。先頭レコードをそのまま採用すると、シリーズ名が他の巻と正規化キーが
    /// 一致しなくなりシリーズが分裂してしまう不具合があった。
    func test_fetchMetadata_duplicateNDLRecordsForSameISBN_prefersNonParallelTitleAndMergesVolume() async throws {
        let xml = """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>
            <item>
              <dc:title>Hunter×hunter = ハンター ハンター</dc:title>
              <dcndl:volume>1</dcndl:volume>
              <category>図書</category>
            </item>
            <item>
              <dc:title>Hunter×hunter</dc:title>
              <dcndl:volume>no.1</dcndl:volume>
              <category>図書</category>
            </item>
          </channel>
        </rss>
        """
        let service = makeService(xml: xml)
        let metadata = try await service.fetchMetadata(isbn: "9784088725710")

        XCTAssertEqual(metadata.seriesName, "Hunter×hunter", "他の巻と同じ正規化キーになるよう、並列タイトルでない表記を優先すること")
        XCTAssertEqual(metadata.volumeNumber, 1, "巻数は別レコードからでも数字表記のものを拾えること")
    }

    func test_fetchMetadata_bookWithoutVolume_returnsNilSeriesInfo() async throws {
        let xml = """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>
            <item>
              <dc:title>三体</dc:title>
              <category>図書</category>
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

    /// 回帰テスト: ISBN検索であっても、図書以外のメディア（例: 何らかの理由で紛れ込んだ
    /// 関連グッズ等）を巻数判定に使わないこと。図書のレコードが他にあればそちらを使う。
    func test_fetchMetadata_ignoresNonBookCategoryItems() async throws {
        let xml = """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>
            <item>
              <dc:title>ONE PIECE</dc:title>
              <dcndl:volume>115</dcndl:volume>
              <category>映像資料</category>
              <category>記録メディア</category>
            </item>
          </channel>
        </rss>
        """
        let service = makeService(xml: xml)
        do {
            _ = try await service.fetchMetadata(isbn: "9784088851303")
            XCTFail("図書以外のレコードしかない場合はnotFoundになるべき")
        } catch let error as NDLSearchError {
            XCTAssertEqual(error, .notFound)
        }
    }

    /// 回帰テスト: 実際に確認したONE PIECE 115巻のケース（dcndl:volumeが"巻115"表記）。
    /// 以前は数字のみの表記しか受け付けておらず、この本はシリーズ判定に失敗していた。
    func test_fetchMetadata_kanPrefixVolume_parsesSeriesAndVolume() async throws {
        let xml = """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>
            <item>
              <dc:title>ONE PIECE</dc:title>
              <dcndl:volume>巻115</dcndl:volume>
              <category>図書</category>
              <category>紙</category>
            </item>
          </channel>
        </rss>
        """
        let service = makeService(xml: xml)
        let metadata = try await service.fetchMetadata(isbn: "9784088851303")

        XCTAssertEqual(metadata.seriesName, "ONE PIECE")
        XCTAssertEqual(metadata.volumeNumber, 115)
    }

    /// 回帰テスト: 転生したらスライムだった件のように、上巻・下巻が別ISBNの別レコードとして
    /// 存在し、どちらも同じ巻数（"1[上]"、"1[下]"）を共有するケース。巻数はNを採用しつつ、
    /// タイトルにマーカーを残して本棚側で見分けられるようにする。
    func test_fetchMetadata_splitVolumeMarker_keepsMarkerInTitle() async throws {
        let xml = """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>
            <item>
              <dc:title>転生したらスライムだった件</dc:title>
              <dcndl:volume>1[上]</dcndl:volume>
              <category>図書</category>
            </item>
          </channel>
        </rss>
        """
        let service = makeService(xml: xml)
        let metadata = try await service.fetchMetadata(isbn: "9781234567890")

        XCTAssertEqual(metadata.seriesName, "転生したらスライムだった件")
        XCTAssertEqual(metadata.volumeNumber, 1)
        XCTAssertEqual(metadata.title, "転生したらスライムだった件 1(上)")
    }

    /// 回帰テスト: 本好きの下剋上のように「部」単位で巻数が振り直されるシリーズは、
    /// 部ごとに別シリーズとして扱う（seriesNameに「第N部」を含める）。
    func test_fetchMetadata_partSplitVolume_appendsPartToSeriesName() async throws {
        let xml = """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>
            <item>
              <dc:title>本好きの下剋上</dc:title>
              <dcndl:volume>第1部[2]</dcndl:volume>
              <category>図書</category>
            </item>
          </channel>
        </rss>
        """
        let service = makeService(xml: xml)
        let metadata = try await service.fetchMetadata(isbn: "9781234567891")

        XCTAssertEqual(metadata.seriesName, "本好きの下剋上 第1部")
        XCTAssertEqual(metadata.volumeNumber, 2, "numberは部内の巻数を表す")
    }

    // MARK: - fetchSeriesVolumeCount（「欠番なしの場合のみ採用」ルール）

    private struct FixtureItem {
        let title: String
        let volume: String?
        var categories: [String] = ["図書", "紙"]
    }

    private func makeSeriesSearchXML(items: [FixtureItem]) -> String {
        let itemsXML = items.map { item -> String in
            let volumeTag = item.volume.map { "<dcndl:volume>\($0)</dcndl:volume>" } ?? ""
            let categoryTags = item.categories.map { "<category>\($0)</category>" }.joined()
            return "<item><dc:title>\(item.title)</dc:title>\(volumeTag)\(categoryTags)</item>"
        }.joined()
        return """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>\(itemsXML)</channel>
        </rss>
        """
    }

    func test_fetchSeriesVolumeCount_noGaps_returnsMaxVolume() async throws {
        // 実際に確認した鬼滅の刃（1〜23巻、欠番なし）のケースを模したデータ
        let items = (1...23).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(count, 23)
    }

    func test_fetchSeriesVolumeCount_gapPartway_returnsOnlyTheLeadingConsecutiveRun() async throws {
        // 実際に確認した「著者名フィルタなし」のケース（1,10〜17巻しか取れず、2〜9,18〜23が歯抜け）を模したデータ。
        // 誤った既刊数（17）を自信ありげに返すのは避けつつ、1巻から連続して確認できる区間
        // （この場合は1巻のみ）までは既刊数として採用する。
        let items = ([1] + Array(10...17)).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(count, 1, "2巻の欠番以降は信頼できないため切り捨て、1巻から連続する区間のみ採用すること")
    }

    /// 回帰テスト: 実際にNDLで確認したHUNTER×HUNTERのケース（1〜16巻は連続して存在するが
    /// 17巻の数字表記レコードがNDLに存在せず、18巻だけ単発でヒットする）を模したデータ。
    /// 「1巻から不明。」ではユーザー体験として物足りないため、17巻の欠番より前（16巻）までを
    /// 既刊総数として採用する。欠番の先にある18巻は信頼せず切り捨てる。
    func test_fetchSeriesVolumeCount_gapNearEnd_returnsVolumesBeforeTheGap() async throws {
        var items = (1...16).map { FixtureItem(title: "HUNTER×HUNTER", volume: String($0)) }
        items.append(FixtureItem(title: "HUNTER×HUNTER", volume: "18")) // 17巻は欠番、18巻だけ単発でヒット
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "HUNTER×HUNTER")
        XCTAssertEqual(count, 16, "17巻の欠番より後の18巻は信頼できないため切り捨て、16巻までを既刊数とすること")
    }

    func test_fetchSeriesVolumeCount_firstVolumeMissing_returnsNil() async throws {
        // 1巻自体が見つからない場合は連続区間の起点が無く、そもそも判断のしようがない
        let items = (2...5).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertNil(count, "1巻が見つからない場合は不明とすること")
    }

    /// 回帰テスト: 実際に確認したONE PIECEのケース（dcndl:volumeが"巻1"〜"巻N"表記）。
    /// 以前は数字のみの表記しか受け付けておらず、既刊数が常に「不明」になっていた。
    func test_fetchSeriesVolumeCount_acceptsKanPrefixVolumeFormat() async throws {
        let items = (1...3).map { FixtureItem(title: "ONE PIECE", volume: "巻\($0)") }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")
        XCTAssertEqual(count, 3)
    }

    func test_fetchSeriesVolumeCount_ignoresMagazineIssueNumberFormat() async throws {
        // 週刊誌の号数（No.N）は単行本の巻数と対応しないため、依然として除外すること
        let items = [
            FixtureItem(title: "ONE PIECE", volume: "No.1"),
            FixtureItem(title: "ONE PIECE", volume: "No.2"),
            FixtureItem(title: "ONE PIECE", volume: "No.3")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")
        XCTAssertNil(count)
    }

    func test_fetchSeriesVolumeCount_ignoresItemsWithDifferentTitle() async throws {
        var items = (1...5).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        items.append(FixtureItem(title: "鬼滅の刃イラスト集", volume: "10")) // タイトル完全一致しない関連グッズ等
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(count, 5, "タイトルが完全一致しない項目（関連グッズ等）は既刊数の計算に含めないこと")
    }

    /// 回帰テスト: タイトルが一致していても、図書以外のメディア（アニメ円盤・CD等）は
    /// 独自の採番体系を持ち、単行本の巻数とは無関係なため除外すること。
    func test_fetchSeriesVolumeCount_ignoresNonBookCategoryItems() async throws {
        var items = (1...5).map { FixtureItem(title: "銀魂", volume: String($0)) }
        // 実際に確認したアニメ円盤の採番（category=映像資料）。数字だけ見ると6巻に見えてしまう。
        items.append(FixtureItem(title: "銀魂", volume: "6", categories: ["映像資料", "記録メディア"]))
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "銀魂")
        XCTAssertEqual(count, 5, "図書以外のメディアの巻数は既刊数の計算に含めないこと")
    }

    func test_fetchSeriesVolumeCount_noMatchingItems_returnsNil() async throws {
        let service = makeService(xml: makeSeriesSearchXML(items: []))
        let count = try await service.fetchSeriesVolumeCount(seriesName: "存在しないシリーズ")
        XCTAssertNil(count)
    }

    /// 回帰テスト: 実際に発生した不具合（HUNTER×HUNTERのムック本混在時に既刊数が「不明」に
    /// なったり戻ったりする）の一因。NDL側の項目タイトルが大文字小文字・全角半角のみ異なる場合、
    /// 完全一致（==）比較では不一致になり既刊数が「不明」になっていた。
    /// SeriesKeyNormalizerによる正規化後の比較で表記ゆれを吸収できることを確認する。
    func test_fetchSeriesVolumeCount_matchesTitlesDifferingOnlyByCaseOrWidth_returnsCount() async throws {
        let items = (1...5).map { FixtureItem(title: "ＨＵＮＴＥＲ×ＨＵＮＴＥＲ", volume: String($0)) } // 全角+大文字
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "Hunter×Hunter")
        XCTAssertEqual(count, 5, "大文字小文字・全角半角の表記差は正規化して同一シリーズとみなすこと")
    }

    /// 回帰テスト: 本好きの下剋上のように「タイトル 第N部」というseriesNameで問い合わせた場合、
    /// NDL検索には部を除いた元のタイトルを使い、結果は対象の部のレコードのみに絞り込むこと。
    func test_fetchSeriesVolumeCount_partSplitSeriesName_queriesBaseTitleAndFiltersToPart() async throws {
        var items = (1...3).map { FixtureItem(title: "本好きの下剋上", volume: "第1部[\($0)]") }
        items += (1...5).map { FixtureItem(title: "本好きの下剋上", volume: "第2部[\($0)]") }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let count = try await service.fetchSeriesVolumeCount(seriesName: "本好きの下剋上 第1部")
        XCTAssertEqual(count, 3, "指定した部のレコードのみを対象に既刊数を計算すること")
    }
}
