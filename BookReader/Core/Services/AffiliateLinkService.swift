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

extension URL {
    /// Universal LinkによってAmazonアプリに横取りされるのを避け、確実にSafariで開かせるための変換。
    /// Amazonアプリへ直接遷移すると、Cookieベースのアフィリエイト計測（tag）が効かなくなることを
    /// 実機で確認したための対策。共有シート拡張機能のextensionContext.open(_:)経由でのみ使用する
    /// （アプリ本体側はSFSafariViewControllerで開くためこの変換は不要、そちらはUniversal Link
    /// 解決を経由しないので最初からAmazonアプリに横取りされない）。
    var forcedToOpenInSafari: URL {
        guard absoluteString.hasPrefix("https://") else { return self }
        return URL(string: "x-safari-\(absoluteString)") ?? self
    }
}
