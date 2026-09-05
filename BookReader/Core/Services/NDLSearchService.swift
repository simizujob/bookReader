import Foundation

enum NDLSearchError: Error, Equatable {
    case notFound
    case timeout
    case decodingFailed
    case network(String)
}

/// 国立国会図書館サーチ（https://ndlsearch.ndl.go.jp/）連携。
/// 国内で出版される書籍は国立国会図書館法により納本が義務付けられているため、
/// openBD・Open Libraryよりもさらに網羅性が高い（無料・APIキー不要）。
/// 巻数（dcndl:volume）を構造化フィールドとして提供するため、TitleParserによる
/// タイトル文字列からの推定よりも信頼できる。ただし表紙画像は提供されない。
///
/// 巻数の表記はNDL内でも統一されておらず多数のバリエーションが存在する（NDLVolumeParser参照）。
/// 安全と判断できるパターンのみを許可リスト化し、それ以外は「不明」として扱う
/// ベストエフォート方針を採る（要件定義書14章・詳細設計書9章参照）。
final class NDLSearchService: BookMetadataFetching {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            self.session = URLSession(configuration: configuration)
        }
    }

    func fetchMetadata(isbn: String) async throws -> BookMetadata {
        guard var components = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/opensearch") else {
            throw NDLSearchError.decodingFailed
        }
        components.queryItems = [URLQueryItem(name: "isbn", value: isbn)]
        guard let url = components.url else { throw NDLSearchError.decodingFailed }

        let data = try await fetchData(from: url)
        let items = NDLResponseParser().parseAll(data).filter(\.isBook)
        guard let title = Self.preferredTitle(among: items), !title.isEmpty else {
            throw NDLSearchError.notFound
        }

        // 同一ISBNに対しNDLが新旧複数のレコードを重複して持つことがある（例: 1998年刊行の
        // HUNTER×HUNTER 1巻は、巻数が数字で入った並列タイトル表記のレコードと、シリーズ内の
        // 他の巻と同じ体裁のタイトルを持つレコードが別々に存在する）。片方だけを見ると、
        // タイトル表記のズレでシリーズが分裂したり、巻数が取得できなかったりするため、
        // 全レコードを横断してタイトル・巻数それぞれ最も使えるものを選ぶ。
        guard let parsed = items.lazy.compactMap({ $0.volume.flatMap(NDLVolumeParser.parse) }).first else {
            return BookMetadata(title: title)
        }

        // 「第1部[2]」のように部単位で巻数が振り直されるシリーズは、部ごとに別シリーズとして扱う
        // （そうしないと部をまたいで同じ巻数が重複し、既刊数判定が意味を成さなくなるため）。
        let seriesName = parsed.part.map { "\(title) 第\($0)部" } ?? title
        // 上巻/中巻/下巻のように同じ巻数を複数の本が共有する場合は、タイトル末尾にマーカーを
        // 残しておく（SeriesProgressCalculatorが本棚の巻一覧で見分けられるようにするため）。
        let volumeLabel = parsed.marker.map { "\(parsed.number)(\($0))" } ?? "\(parsed.number)"
        return BookMetadata(
            title: "\(seriesName) \(volumeLabel)",
            seriesName: seriesName,
            volumeNumber: parsed.number
        )
    }

    /// NDLの並列タイトル表記（例: "Hunter×hunter = ハンター ハンター"）はISBD形式の代替タイトル
    /// 併記であり、シリーズ内の他の巻とは異なる正規化キーになってしまう。並列表記でないタイトルを
    /// 持つレコードが他にあればそちらを優先し、なければ先頭のレコードにフォールバックする。
    private static func preferredTitle(among items: [NDLResponseParser.Item]) -> String? {
        let titles = items.compactMap(\.title).filter { !$0.isEmpty }
        return titles.first { !$0.contains(" = ") } ?? titles.first
    }

    /// 既刊総数のベストエフォート推定。タイトルで検索し、タイトルが完全一致かつ巻数が
    /// NDLVolumeParserで安全と判断できる表記の項目を集める。
    ///
    /// 著者名によるクエリ絞り込みは検証の結果採用しないことにした（生データの読点・生年付記・
    /// 異体字などの表記ゆれが原因で、プログラム的に正しいクエリを組み立てられないことを確認済み）。
    /// 絞り込みなしでは1ページ（最大200件）に無関係な関連商品が混ざり、本来の巻が
    /// 歯抜けで取得されることがある（例: 1,10〜17巻しか取れず本来23巻あるようなケース）。
    /// 特にタイトルが一般的な単語と被る作品（"ONE PIECE"＝洋服の意でもある等）では、
    /// 200件の枠が無関係な文献で埋まり単行本が1件もヒットしないことを実データで確認した。
    /// このアプリはF-05を漫画のみ対象としている（要件定義書参照）ため、NDLの分類コード
    /// （NDC）で漫画区分「726.1」に絞り込むことで、無関係な文献・関連グッズ・アニメ円盤等を
    /// 大幅に除外できる（実データで検証済み。この絞り込みだけで既刊数の精度が大きく改善した）。
    ///
    /// 既刊総数は**1巻から連続して確認できた最大巻**を採用する（例: 1〜16巻が確認でき17巻だけ
    /// 欠けている場合は16を返す）。18巻のように欠番の先に単発でヒットする巻は、そのISBNだけ
    /// 別レコードでたまたま見つかっただけの可能性があり信頼できないため切り捨てる。
    /// 1巻自体が見つからない場合は連続区間の起点が無く判断できないため不明（nil）とする。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
        // 「本好きの下剋上 第1部」のような部分割シリーズ名は、NDL側のdc:titleには「部」を
        // 含まないため、検索クエリには部を除いた元のシリーズ名を使い、結果は対象の部の
        // レコードのみに絞り込む。
        let (queryTitle, targetPart) = Self.splitPartSuffix(seriesName)

        guard var components = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/opensearch") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: queryTitle),
            URLQueryItem(name: "ndc", value: "726.1"),
            URLQueryItem(name: "cnt", value: "200")
        ]
        guard let url = components.url, let data = try? await fetchData(from: url) else { return nil }

        // タイトルの完全一致（==）は大文字小文字・全角半角等の些細な表記差でも不一致になり、
        // 同じシリーズなのに既刊数が「不明」になる不具合の原因だった。SeriesKeyNormalizerによる
        // 正規化後の比較にすることで、表記ゆれを吸収する。
        let normalizedTarget = SeriesKeyNormalizer.normalize(queryTitle)
        let volumes = Set(
            NDLResponseParser().parseAll(data)
                .filter(\.isBook) // アニメ円盤・CD等、無関係なメディアを除外する
                .filter { $0.title.map(SeriesKeyNormalizer.normalize) == normalizedTarget }
                .compactMap { item -> Int? in
                    guard let parsed = item.volume.flatMap(NDLVolumeParser.parse) else { return nil }
                    guard parsed.part == targetPart else { return nil }
                    return parsed.number
                }
        )
        return Self.longestConsecutiveRun(from: volumes)
    }

    /// 1から連番で途切れずに存在する最大値を返す（例: {1,2,3,5,6} → 3）。1が無ければnil。
    private static func longestConsecutiveRun(from volumes: Set<Int>) -> Int? {
        guard volumes.contains(1) else { return nil }
        var latest = 1
        while volumes.contains(latest + 1) {
            latest += 1
        }
        return latest
    }

    private static let partSuffixPattern = try! NSRegularExpression(pattern: #"^(.+) 第(\d+)部$"#)

    /// 「タイトル 第N部」から元のタイトルと部番号を取り出す。部分割でなければ(seriesName, nil)を返す。
    private static func splitPartSuffix(_ seriesName: String) -> (queryTitle: String, part: Int?) {
        let range = NSRange(seriesName.startIndex..<seriesName.endIndex, in: seriesName)
        guard let match = partSuffixPattern.firstMatch(in: seriesName, range: range),
              let titleRange = Range(match.range(at: 1), in: seriesName),
              let partRange = Range(match.range(at: 2), in: seriesName),
              let part = Int(seriesName[partRange])
        else {
            return (seriesName, nil)
        }
        return (String(seriesName[titleRange]), part)
    }

    private func fetchData(from url: URL) async throws -> Data {
        do {
            let (data, _) = try await session.data(from: url)
            return data
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw NDLSearchError.timeout
            }
            throw NDLSearchError.network(error.localizedDescription)
        }
    }
}

/// NDL SearchのOpenSearch（RSS + Dublin Core）レスポンスから<item>のタイトル・巻数を抽出する。
final class NDLResponseParser: NSObject, XMLParserDelegate {
    struct Item: Equatable {
        var title: String?
        var volume: String?
        var categories: [String] = []

        /// 紙・電子の「本」であることを示す。アニメ円盤（映像資料）やCD（録音資料）等、
        /// タイトルは一致するが巻数の意味が全く異なる無関係なメディアを除外するために使う
        /// （実データで、タイトルが一致する漫画のアニメBlu-rayが独自の巻数体系で
        /// 混在することを確認済み）。
        var isBook: Bool { categories.contains("図書") }
    }

    private var insideItem = false
    private var currentElement = ""
    private var currentText = ""
    private var currentItem = Item()
    private var items: [Item] = []

    func parseFirst(_ data: Data) -> Item? {
        parseAll(data).first
    }

    func parseAll(_ data: Data) -> [Item] {
        items = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""
        if elementName == "item" {
            insideItem = true
            currentItem = Item()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard insideItem else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "dc:title":
            if currentItem.title == nil { currentItem.title = text }
        case "dcndl:volume":
            currentItem.volume = text
        case "category":
            currentItem.categories.append(text)
        case "item":
            items.append(currentItem)
            insideItem = false
        default:
            break
        }
        currentText = ""
    }
}
