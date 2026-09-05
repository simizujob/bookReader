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
/// 巻数の表記はNDL内でも統一されておらず、数字のみ（"5"）・「巻」+数字（"巻90"）・
/// 古い登録の漢数字（"巻一"）などが混在することを実データで確認済み。ベストエフォート方針として
/// 数字のみの表記だけを対象とし、それ以外は「不明」として扱う（要件定義書14章・詳細設計書9章参照）。
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
        guard let item = NDLResponseParser().parseFirst(data), let title = item.title, !title.isEmpty else {
            throw NDLSearchError.notFound
        }

        let volume = item.volume.flatMap(Self.parseDigitsOnly)
        if let volume {
            return BookMetadata(title: "\(title) \(volume)", seriesName: title, volumeNumber: volume)
        }
        return BookMetadata(title: title)
    }

    /// 既刊総数のベストエフォート推定。タイトルで検索し、タイトルが完全一致かつ巻数が
    /// 数字のみで表記されている項目を集める。
    ///
    /// 著者名によるクエリ絞り込みは検証の結果採用しないことにした（生データの読点・生年付記・
    /// 異体字などの表記ゆれが原因で、プログラム的に正しいクエリを組み立てられないことを確認済み）。
    /// 絞り込みなしでは1ページ（最大200件）に無関係な関連商品が混ざり、本来の巻が
    /// 歯抜けで取得されることがある（例: 1,10〜17巻しか取れず本来23巻あるようなケース）。
    /// 誤った既刊数を自信ありげに返すのは「不明」より悪いため、
    /// **1巻から検出した最大巻まで一つも欠番がない場合にのみ**採用し、
    /// 少しでも歯抜けがあれば信頼できないデータとみなしnilを返す。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
        guard var components = URLComponents(string: "https://ndlsearch.ndl.go.jp/api/opensearch") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: seriesName),
            URLQueryItem(name: "cnt", value: "200")
        ]
        guard let url = components.url, let data = try? await fetchData(from: url) else { return nil }

        // タイトルの完全一致（==）は大文字小文字・全角半角等の些細な表記差でも不一致になり、
        // 同じシリーズなのに既刊数が「不明」になる不具合の原因だった。SeriesKeyNormalizerによる
        // 正規化後の比較にすることで、表記ゆれを吸収する。
        let normalizedTarget = SeriesKeyNormalizer.normalize(seriesName)
        let volumes = Set(
            NDLResponseParser().parseAll(data)
                .filter { $0.title.map(SeriesKeyNormalizer.normalize) == normalizedTarget }
                .compactMap { $0.volume.flatMap(Self.parseDigitsOnly) }
        )
        guard let maxVolume = volumes.max(), maxVolume > 0 else { return nil }

        let hasNoGaps = (1...maxVolume).allSatisfy { volumes.contains($0) }
        return hasNoGaps ? maxVolume : nil
    }

    /// 数字のみで構成された巻数表記のみを受け付ける（"5" は可、"巻5"・"巻一"・"No. 71" は不可）。
    private static func parseDigitsOnly(_ text: String) -> Int? {
        guard text.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return nil }
        return Int(text)
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
        case "item":
            items.append(currentItem)
            insideItem = false
        default:
            break
        }
        currentText = ""
    }
}
