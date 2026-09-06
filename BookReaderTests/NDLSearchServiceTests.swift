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
        var isbn: String? = nil
        var creator: String? = nil
        var titleTranscription: String? = nil
    }

    private func makeSeriesSearchXML(items: [FixtureItem]) -> String {
        let itemsXML = items.map { item -> String in
            let volumeTag = item.volume.map { "<dcndl:volume>\($0)</dcndl:volume>" } ?? ""
            let categoryTags = item.categories.map { "<category>\($0)</category>" }.joined()
            let isbnTag = item.isbn.map {
                "<dc:identifier xsi:type=\"dcndl:ISBN\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\($0)</dc:identifier>"
            } ?? ""
            let creatorTag = item.creator.map { "<dc:creator>\($0)</dc:creator>" } ?? ""
            let transcriptionTag = item.titleTranscription.map { "<dcndl:titleTranscription>\($0)</dcndl:titleTranscription>" } ?? ""
            return "<item><dc:title>\(item.title)</dc:title>\(volumeTag)\(categoryTags)\(isbnTag)\(creatorTag)\(transcriptionTag)</item>"
        }.joined()
        return """
        <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcndl="http://ndl.go.jp/dcndl/terms/" version="2.0">
          <channel>\(itemsXML)</channel>
        </rss>
        """
    }

    /// 回帰テスト: 実際に確認したケース（"ONE PIECE"というタイトルが服飾・学術文献等の
    /// 無関係な文献と大量に被り、絞り込みなしでは200件の枠内に単行本が1件もヒットしない）。
    /// NDLの分類コード（NDC）で漫画区分「726.1」に絞り込むクエリを送っていることを確認する。
    func test_fetchSeriesVolumeCount_includesMangaNDCFilterInQuery() async throws {
        var capturedURL: URL?
        StubURLProtocol.responseProvider = { url in
            capturedURL = url
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Self.notFoundResponseXML.data(using: .utf8)!, response)
        }
        let service = NDLSearchService(session: StubURLProtocol.makeSession())
        _ = try? await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")

        let queryItems = URLComponents(url: try XCTUnwrap(capturedURL), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(queryItems?.first { $0.name == "ndc" }?.value, "726.1")
    }

    /// 回帰テスト: 実際に確認したONE PIECEのケース（cnt=200では91巻以降が枠に収まらず、
    /// 実際は115巻まで連番で存在するのに90巻で打ち切られてしまっていた）。
    func test_fetchSeriesVolumeCount_requestsLargerPageSizeThanTheOldDefault() async throws {
        var capturedURL: URL?
        StubURLProtocol.responseProvider = { url in
            capturedURL = url
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Self.notFoundResponseXML.data(using: .utf8)!, response)
        }
        let service = NDLSearchService(session: StubURLProtocol.makeSession())
        _ = try? await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")

        let queryItems = URLComponents(url: try XCTUnwrap(capturedURL), resolvingAgainstBaseURL: false)?.queryItems
        let cnt = queryItems?.first { $0.name == "cnt" }?.value.flatMap(Int.init)
        XCTAssertEqual(cnt, 500, "旧cnt=200では長期連載作品の巻数が枠に収まりきらないことを実データで確認した")
    }

    func test_fetchSeriesVolumeCount_noGaps_returnsMaxVolume() async throws {
        // 実際に確認した鬼滅の刃（1〜23巻、欠番なし）のケースを模したデータ
        let items = (1...23).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(result?.total, 23)
    }

    /// 回帰テスト: 実際に確認したONE PIECE（115巻まで欠番なし）のような長期連載作品でも、
    /// 応答件数が十分であれば正しく最新巻まで既刊数を判定できること。
    func test_fetchSeriesVolumeCount_longRunningSeriesWithManyVolumes_returnsMaxVolume() async throws {
        let items = (1...115).map { FixtureItem(title: "ONE PIECE", volume: "巻\($0)") }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")
        XCTAssertEqual(result?.total, 115)
    }

    func test_fetchSeriesVolumeCount_gapPartway_returnsOnlyTheLeadingConsecutiveRun() async throws {
        // 実際に確認した「著者名フィルタなし」のケース（1,10〜17巻しか取れず、2〜9,18〜23が歯抜け）を模したデータ。
        // 誤った既刊数（17）を自信ありげに返すのは避けつつ、1巻から連続して確認できる区間
        // （この場合は1巻のみ）までは既刊数として採用する。
        let items = ([1] + Array(10...17)).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(result?.total, 1, "2巻の欠番以降は信頼できないため切り捨て、1巻から連続する区間のみ採用すること")
    }

    /// 回帰テスト: 実際にNDLで確認したHUNTER×HUNTERのケース（1〜16巻は連続して存在するが
    /// 17巻の数字表記レコードがNDLに存在せず、18巻だけ単発でヒットする）を模したデータ。
    /// 「1巻から不明。」ではユーザー体験として物足りないため、17巻の欠番より前（16巻）までを
    /// 既刊総数として採用する。欠番の先にある18巻は信頼せず切り捨てる。
    func test_fetchSeriesVolumeCount_gapNearEnd_returnsVolumesBeforeTheGap() async throws {
        var items = (1...16).map { FixtureItem(title: "HUNTER×HUNTER", volume: String($0)) }
        items.append(FixtureItem(title: "HUNTER×HUNTER", volume: "18")) // 17巻は欠番、18巻だけ単発でヒット
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "HUNTER×HUNTER")
        XCTAssertEqual(result?.total, 16, "17巻の欠番より後の18巻は信頼できないため切り捨て、16巻までを既刊数とすること")
    }

    func test_fetchSeriesVolumeCount_firstVolumeMissing_returnsNil() async throws {
        // 1巻自体が見つからない場合は連続区間の起点が無く、そもそも判断のしようがない
        let items = (2...5).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertNil(result, "1巻が見つからない場合は不明とすること")
    }

    /// 回帰テスト: 実際に確認したONE PIECEのケース（dcndl:volumeが"巻1"〜"巻N"表記）。
    /// 以前は数字のみの表記しか受け付けておらず、既刊数が常に「不明」になっていた。
    func test_fetchSeriesVolumeCount_acceptsKanPrefixVolumeFormat() async throws {
        let items = (1...3).map { FixtureItem(title: "ONE PIECE", volume: "巻\($0)") }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")
        XCTAssertEqual(result?.total, 3)
    }

    func test_fetchSeriesVolumeCount_ignoresMagazineIssueNumberFormat() async throws {
        // 週刊誌の号数（No.N）は単行本の巻数と対応しないため、依然として除外すること
        let items = [
            FixtureItem(title: "ONE PIECE", volume: "No.1"),
            FixtureItem(title: "ONE PIECE", volume: "No.2"),
            FixtureItem(title: "ONE PIECE", volume: "No.3")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")
        XCTAssertNil(result)
    }

    func test_fetchSeriesVolumeCount_ignoresItemsWithDifferentTitle() async throws {
        var items = (1...5).map { FixtureItem(title: "鬼滅の刃", volume: String($0)) }
        items.append(FixtureItem(title: "鬼滅の刃イラスト集", volume: "10")) // タイトル完全一致しない関連グッズ等
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(result?.total, 5, "タイトルが完全一致しない項目（関連グッズ等）は既刊数の計算に含めないこと")
    }

    /// 回帰テスト: タイトルが一致していても、図書以外のメディア（アニメ円盤・CD等）は
    /// 独自の採番体系を持ち、単行本の巻数とは無関係なため除外すること。
    func test_fetchSeriesVolumeCount_ignoresNonBookCategoryItems() async throws {
        var items = (1...5).map { FixtureItem(title: "銀魂", volume: String($0)) }
        // 実際に確認したアニメ円盤の採番（category=映像資料）。数字だけ見ると6巻に見えてしまう。
        items.append(FixtureItem(title: "銀魂", volume: "6", categories: ["映像資料", "記録メディア"]))
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "銀魂")
        XCTAssertEqual(result?.total, 5, "図書以外のメディアの巻数は既刊数の計算に含めないこと")
    }

    func test_fetchSeriesVolumeCount_noMatchingItems_returnsNil() async throws {
        let service = makeService(xml: makeSeriesSearchXML(items: []))
        let result = try await service.fetchSeriesVolumeCount(seriesName: "存在しないシリーズ")
        XCTAssertNil(result)
    }

    /// 回帰テスト: 実際に発生した不具合（HUNTER×HUNTERのムック本混在時に既刊数が「不明」に
    /// なったり戻ったりする）の一因。NDL側の項目タイトルが大文字小文字・全角半角のみ異なる場合、
    /// 完全一致（==）比較では不一致になり既刊数が「不明」になっていた。
    /// SeriesKeyNormalizerによる正規化後の比較で表記ゆれを吸収できることを確認する。
    func test_fetchSeriesVolumeCount_matchesTitlesDifferingOnlyByCaseOrWidth_returnsCount() async throws {
        let items = (1...5).map { FixtureItem(title: "ＨＵＮＴＥＲ×ＨＵＮＴＥＲ", volume: String($0)) } // 全角+大文字
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "Hunter×Hunter")
        XCTAssertEqual(result?.total, 5, "大文字小文字・全角半角の表記差は正規化して同一シリーズとみなすこと")
    }

    /// 回帰テスト: 本好きの下剋上のように「タイトル 第N部」というseriesNameで問い合わせた場合、
    /// NDL検索には部を除いた元のタイトルを使い、結果は対象の部のレコードのみに絞り込むこと。
    func test_fetchSeriesVolumeCount_partSplitSeriesName_queriesBaseTitleAndFiltersToPart() async throws {
        var items = (1...3).map { FixtureItem(title: "本好きの下剋上", volume: "第1部[\($0)]") }
        items += (1...5).map { FixtureItem(title: "本好きの下剋上", volume: "第2部[\($0)]") }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "本好きの下剋上 第1部")
        XCTAssertEqual(result?.total, 3, "指定した部のレコードのみを対象に既刊数を計算すること")
    }

    /// 既刊数が自動判明した際、巻ごとのISBNも一緒に取得できること（Amazon購入リンクを
    /// キーワード検索ではなくISBN検索にするため、SeriesVolumeCountRefreshServiceが使用する）。
    func test_fetchSeriesVolumeCount_collectsISBNPerVolume() async throws {
        let items = (1...3).map {
            FixtureItem(title: "鬼滅の刃", volume: String($0), isbn: "978-4-08-000000-\($0)")
        }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")
        XCTAssertEqual(result?.isbnsByVolume[1], "9784080000001")
        XCTAssertEqual(result?.isbnsByVolume[2], "9784080000002")
        XCTAssertEqual(result?.isbnsByVolume[3], "9784080000003")
    }

    /// 回帰テスト: 実際に確認したONE PIECEのケース。同じタイトルで、本来の単行本（"巻N"表記、
    /// ジャンプコミックス）とは別に、総集編/アニメコミックス（"SJR"扱い、"N (副題)"という
    /// 「巻」なし裸数字+副題の表記、独自の1〜23の巻数体系）が同一タイトルで別途登録されており、
    /// 両者が混ざると総集編側のISBNが本来の巻のISBNとして誤って採用されてしまっていた。
    /// 「巻」付き表記が1件でもあれば、「巻」なし表記は別編集とみなして除外すること。
    func test_fetchSeriesVolumeCount_mixedEditionsWithSameTitle_ignoresNonKanPrefixedReissue() async throws {
        var items = (1...23).map { volume in
            FixtureItem(title: "ONE PIECE", volume: "巻\(volume)", isbn: "978410000\(String(format: "%04d", volume))")
        }
        // 総集編（SJR）側。独自ISBNを持ち、本来の巻とは無関係。
        items.append(FixtureItem(title: "ONE PIECE", volume: "1 (東の海編)", isbn: "9784199999901"))
        items.append(FixtureItem(title: "ONE PIECE", volume: "11 (空島編)", isbn: "9784199999911"))
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "ONE PIECE")
        XCTAssertEqual(result?.total, 23)
        XCTAssertEqual(result?.isbnsByVolume[1], "9784100000001", "総集編側のISBNではなく本来の単行本（巻付き表記）のISBNを採用すること")
        XCTAssertEqual(result?.isbnsByVolume[11], "9784100000011", "総集編側のISBNではなく本来の単行本（巻付き表記）のISBNを採用すること")
    }

    /// 回帰テスト: 「巻」付き表記が1件も無いタイトル（ゴールデンカムイ等、裸数字+副題表記のみを
    /// 使う作品）では、別編集混在フィルタが誤発動せず従来通り全件を既刊数計算に含めること。
    func test_fetchSeriesVolumeCount_onlyBareSubtitleFormatExists_stillTrustsAllItems() async throws {
        let items = (1...10).map { FixtureItem(title: "ゴールデンカムイ", volume: "\($0) (副題)") }
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "ゴールデンカムイ")
        XCTAssertEqual(result?.total, 10, "「巻」付き表記が存在しないタイトルでは裸数字+副題表記を除外しないこと")
    }

    // MARK: - searchCandidates（タイトルだけで検索し、候補をユーザーに選ばせる）

    func test_searchCandidates_returnsCandidatesWithCreator() async throws {
        let items = [
            FixtureItem(title: "鬼滅の刃 1", volume: "1", isbn: "9784088801955", creator: "吾峠, 呼世晴"),
            FixtureItem(title: "鬼滅の刃 2", volume: "2", isbn: "9784088801962", creator: "吾峠, 呼世晴")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let candidates = await service.searchCandidates(title: "鬼滅の刃")

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.first?.isbn, "9784088801955")
        XCTAssertEqual(candidates.first?.title, "鬼滅の刃 1")
        XCTAssertEqual(candidates.first?.creator, "吾峠, 呼世晴")
    }

    func test_searchCandidates_deduplicatesByISBN() async throws {
        // NDLは同一ISBNに対し新旧複数レコードを重複して持つことがある
        let items = [
            FixtureItem(title: "三体", volume: nil, isbn: "9784041061059"),
            FixtureItem(title: "三体", volume: nil, isbn: "9784041061059")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let candidates = await service.searchCandidates(title: "三体")

        XCTAssertEqual(candidates.count, 1)
    }

    func test_searchCandidates_excludesItemsWithoutISBN() async throws {
        let items = [FixtureItem(title: "ISBN不明の本", volume: nil, isbn: nil)]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let candidates = await service.searchCandidates(title: "ISBN不明の本")

        XCTAssertTrue(candidates.isEmpty)
    }

    func test_searchCandidates_excludesNonBookCategoryItems() async throws {
        let items = [
            FixtureItem(title: "アニメ円盤", volume: nil, categories: ["映像資料", "記録メディア"], isbn: "9784000000001")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let candidates = await service.searchCandidates(title: "アニメ円盤")

        XCTAssertTrue(candidates.isEmpty)
    }

    /// 回帰テスト: ユーザーからのフィードバック。"ONE PIECE"（ローマ字表記）をカタカナ読み
    /// "ワンピース"で検索すると、たまたま「ワンピース」という語を含むだけの無関係な商品
    /// （婦人服等）が先に埋もれさせてしまっていた。タイトルの読み仮名（titleTranscription）
    /// による完全一致を、単なる部分一致より上位に並べること。
    func test_searchCandidates_ranksTranscriptionExactMatchAboveUnrelatedSubstringMatch() async throws {
        let items = [
            FixtureItem(
                title: "あーたんのワンピース", volume: nil, isbn: "9784000000099"
            ),
            FixtureItem(
                title: "ONE PIECE", volume: "1", isbn: "9784088725093", titleTranscription: "ワン ピース"
            )
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let candidates = await service.searchCandidates(title: "ワンピース")

        XCTAssertEqual(candidates.first?.isbn, "9784088725093", "読み仮名が完全一致する本来の作品を最上位にすること")
    }

    /// 前方一致は部分一致より上位に来ること（例: "鬼滅の刃"で検索した際、"鬼滅の刃 1"のような
    /// 本来欲しい巻が、たまたま途中に含むだけの無関係な本より上位に来る）。
    func test_searchCandidates_prefixMatchRanksAboveSubstringMatch() async throws {
        let items = [
            FixtureItem(title: "○○と学ぶ鬼滅の刃の世界", volume: nil, isbn: "9784000000001"),
            FixtureItem(title: "鬼滅の刃 1", volume: "1", isbn: "9784088801955")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let candidates = await service.searchCandidates(title: "鬼滅の刃")

        XCTAssertEqual(candidates.first?.isbn, "9784088801955")
    }

    /// クエリと全く関連の無いタイトルは候補から除外すること。
    func test_searchCandidates_excludesUnrelatedTitles() async throws {
        let items = [
            FixtureItem(title: "全く関係の無い専門書のタイトル", volume: nil, isbn: "9784000000002"),
            FixtureItem(title: "鬼滅の刃 1", volume: "1", isbn: "9784088801955")
        ]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let candidates = await service.searchCandidates(title: "鬼滅の刃")

        XCTAssertEqual(candidates.map(\.isbn), ["9784088801955"])
    }

    // MARK: - searchPaperEditionISBN（Kindle版ASIN等、ISBN変換に失敗した場合の紙の本再検索）

    /// 回帰テスト: 実機で確認したケース（Kindle版商品ページのURLスラグから推測した
    /// タイトル"プラチナデータ"で紙の本を再検索する）。類似度が十分高い候補が
    /// 1件見つかればそのISBNを返すこと。
    func test_searchPaperEditionISBN_highSimilarityMatch_returnsISBN() async throws {
        let items = [FixtureItem(title: "プラチナデータ", volume: nil, isbn: "9784344421064")]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let isbn = await service.searchPaperEditionISBN(titleHint: "プラチナデータ")
        XCTAssertEqual(isbn, "9784344421064")
    }

    /// URLスラグから推測したタイトルは精度が低いため、類似度が低い場合は
    /// 誤った本を返さずnilとすること。
    func test_searchPaperEditionISBN_lowSimilarityMatch_returnsNil() async throws {
        let items = [FixtureItem(title: "全く関係ない本のタイトル", volume: nil, isbn: "9784344421064")]
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let isbn = await service.searchPaperEditionISBN(titleHint: "プラチナデータ")
        XCTAssertNil(isbn)
    }

    func test_searchPaperEditionISBN_noMatches_returnsNil() async throws {
        let service = makeService(xml: makeSeriesSearchXML(items: []))

        let isbn = await service.searchPaperEditionISBN(titleHint: "存在しない本")
        XCTAssertNil(isbn)
    }

    /// 「1巻から連続して確認できた最大巻」より先（信頼していない範囲）のISBNは持ち出さないこと。
    func test_fetchSeriesVolumeCount_excludesISBNsBeyondTrustedRange() async throws {
        var items = (1...16).map { FixtureItem(title: "HUNTER×HUNTER", volume: String($0), isbn: "978-4-00-000000-\($0)") }
        items.append(FixtureItem(title: "HUNTER×HUNTER", volume: "18", isbn: "9784000000018")) // 17巻は欠番
        let service = makeService(xml: makeSeriesSearchXML(items: items))

        let result = try await service.fetchSeriesVolumeCount(seriesName: "HUNTER×HUNTER")
        XCTAssertEqual(result?.total, 16)
        XCTAssertNil(result?.isbnsByVolume[18], "信頼していない18巻のISBNは持ち出さないこと")
        XCTAssertNotNil(result?.isbnsByVolume[16])
    }
}
