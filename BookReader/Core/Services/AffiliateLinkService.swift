import Foundation

protocol AffiliateLinking {
    func amazonSearchURL(isbn: String) -> URL
    func amazonSearchURL(keywords: String) -> URL
    func amazonProductURL(asin: String) -> URL
}

/// 要件定義書F-05・詳細設計書4.9参照。トラッキングIDは公開が前提の値のためコード直書きで問題ない。
struct AffiliateLinkService: AffiliateLinking {
    private let trackingID = "taros0480x84e-22"

    func amazonSearchURL(isbn: String) -> URL {
        makeSearchURL(keyword: isbn)
    }

    func amazonSearchURL(keywords: String) -> URL {
        makeSearchURL(keyword: keywords)
    }

    /// 共有シート機能（F-XX）で、判定結果画面からAmazonの同じ商品ページへ戻る際に使用する。
    /// 検索結果ページ経由だと商品を特定できない（同名の別版がヒットする等）ため、
    /// ASINが分かっている場合は商品ページへ直接タグを付けて戻す。
    func amazonProductURL(asin: String) -> URL {
        var components = URLComponents(string: "https://www.amazon.co.jp/dp/\(asin)")!
        components.queryItems = [URLQueryItem(name: "tag", value: trackingID)]
        return components.url!
    }

    private func makeSearchURL(keyword: String) -> URL {
        var components = URLComponents(string: "https://www.amazon.co.jp/s")!
        components.queryItems = [
            URLQueryItem(name: "k", value: keyword),
            URLQueryItem(name: "tag", value: trackingID)
        ]
        return components.url!
    }
}
