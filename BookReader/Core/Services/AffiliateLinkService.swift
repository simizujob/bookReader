import Foundation

protocol AffiliateLinking {
    func amazonSearchURL(isbn: String) -> URL
    func amazonSearchURL(keywords: String) -> URL
}

/// 要件定義書F-05・詳細設計書4.9参照。トラッキングIDは公開が前提の値のためコード直書きで問題ない。
struct AffiliateLinkService: AffiliateLinking {
    private let trackingID = "taros0480x84e-22"

    func amazonSearchURL(isbn: String) -> URL {
        makeURL(keyword: isbn)
    }

    func amazonSearchURL(keywords: String) -> URL {
        makeURL(keyword: keywords)
    }

    private func makeURL(keyword: String) -> URL {
        var components = URLComponents(string: "https://www.amazon.co.jp/s")!
        components.queryItems = [
            URLQueryItem(name: "k", value: keyword),
            URLQueryItem(name: "tag", value: trackingID)
        ]
        return components.url!
    }
}
