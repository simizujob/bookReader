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

        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw NDLSearchError.timeout
            }
            throw NDLSearchError.network(error.localizedDescription)
        }

        guard let item = NDLResponseParser().parse(data), let title = item.title, !title.isEmpty else {
            throw NDLSearchError.notFound
        }

        if let volume = item.volume {
            return BookMetadata(title: "\(title) \(volume)", seriesName: title, volumeNumber: volume)
        }
        return BookMetadata(title: title)
    }

    /// NDL SearchにはopenBD同様、既刊総数推定に使えるシリーズ横断検索は今のところ未実装。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
        nil
    }
}

/// NDL SearchのOpenSearch（RSS + Dublin Core）レスポンスから最初の<item>のタイトル・巻数を抽出する。
final class NDLResponseParser: NSObject, XMLParserDelegate {
    struct Item: Equatable {
        var title: String?
        var volume: Int?
    }

    private var insideItem = false
    private var currentElement = ""
    private var currentText = ""
    private var currentItem = Item()
    private var firstItem: Item?

    func parse(_ data: Data) -> Item? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return firstItem
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
            currentItem.volume = Int(text)
        case "item":
            if firstItem == nil { firstItem = currentItem }
            insideItem = false
        default:
            break
        }
        currentText = ""
    }
}
