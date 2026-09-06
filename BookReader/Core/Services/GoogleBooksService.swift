import Foundation

/// タイトルの手掛かりを1件のISBNへ自動確定せず、候補を複数返してユーザーに選ばせる窓口。
/// 買う前チェック画面のタイトル検索（Amazonを開かずに本のタイトルだけで判定したい場合）で使用する。
struct TitleSearchCandidate: Equatable, Identifiable {
    let isbn: String
    let title: String
    let creator: String?
    let coverImageURL: String?
    var id: String { isbn }
}

protocol TitleSearching {
    func searchCandidates(title: String) async -> [TitleSearchCandidate]
}

/// Google Books API（https://developers.google.com/books）によるタイトル検索。
/// NDL Searchは図書館カタログ向けの素朴なキーワード一致で、たまたま検索語を含むだけの
/// 無関係な商品が本来欲しい本より上位に来てしまう問題があった（実機で確認）。Google Booksは
/// 実際の検索エンジンであり関連度が高く、また表紙画像も取得できる（NDLには無い）ため、
/// 候補を見分けやすくなる。
///
/// 実機で確認: APIキー無しのリクエストは1日あたりの割り当てが0件に設定されており、
/// 常に空の結果になっていた（エラーレスポンスだがitemsキーが無いだけなので、デコード自体は
/// 成功し「該当0件」と区別が付かない）。Google Cloud Consoleで発行した無料枠のAPIキーを
/// 付与する。トラッキングIDと同様、iOSアプリのBundle IDで制限をかけた上での直書きを想定。
struct GoogleBooksService: TitleSearching {
    private let apiKey = "AIzaSyCoNON-PC79t0dhGID7X6Fgvd4KPFS2wi0"
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

    func searchCandidates(title: String) async -> [TitleSearchCandidate] {
        guard var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: title),
            URLQueryItem(name: "country", value: "JP"),
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url else { return [] }
        guard let (data, _) = try? await session.data(from: url) else { return [] }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }

        var seenISBNs: Set<String> = []
        var results: [TitleSearchCandidate] = []
        for item in response.items ?? [] {
            guard let isbn = Self.isbn13(from: item.volumeInfo.industryIdentifiers ?? []),
                  !seenISBNs.contains(isbn)
            else { continue }
            seenISBNs.insert(isbn)
            results.append(TitleSearchCandidate(
                isbn: isbn,
                title: item.volumeInfo.title ?? title,
                creator: item.volumeInfo.authors?.joined(separator: "、"),
                // Google Booksの表紙URLはデフォルトでhttp://のため、ATS（App Transport Security）で
                // ブロックされないようhttps://に置き換える（同じパスでhttps配信されることを確認済み）。
                coverImageURL: item.volumeInfo.imageLinks?.thumbnail.map {
                    $0.replacingOccurrences(of: "http://", with: "https://")
                }
            ))
        }
        return results
    }

    /// ISBN_13を優先し、無ければISBN_10をISBN_13へ変換する。どちらも無い場合は候補として使えないためnil。
    private static func isbn13(from identifiers: [Response.Item.VolumeInfo.IndustryIdentifier]) -> String? {
        if let isbn13 = identifiers.first(where: { $0.type == "ISBN_13" })?.identifier {
            return isbn13
        }
        if let isbn10 = identifiers.first(where: { $0.type == "ISBN_10" })?.identifier {
            return ISBNConverter.isbn13(fromASIN: isbn10)
        }
        return nil
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            struct VolumeInfo: Decodable {
                struct IndustryIdentifier: Decodable {
                    let type: String
                    let identifier: String
                }
                struct ImageLinks: Decodable {
                    let thumbnail: String?
                }
                let title: String?
                let authors: [String]?
                let industryIdentifiers: [IndustryIdentifier]?
                let imageLinks: ImageLinks?
            }
            let volumeInfo: VolumeInfo
        }
        let items: [Item]?
    }
}
