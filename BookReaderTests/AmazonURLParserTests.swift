import XCTest
@testable import BookReader

final class AmazonURLParserTests: XCTestCase {
    func test_dpPath_extractsASIN() {
        let url = URL(string: "https://www.amazon.co.jp/dp/4088851306")!
        XCTAssertEqual(AmazonURLParser.extractASIN(from: url), "4088851306")
    }

    func test_dpPathWithTrailingSegments_extractsASIN() {
        let url = URL(string: "https://www.amazon.co.jp/ONE-PIECE-115-%E3%82%B8%E3%83%A3%E3%83%B3%E3%83%97%E3%82%B3%E3%83%9F%E3%83%83%E3%82%AF%E3%82%B9/dp/4088851306/ref=sr_1_1")!
        XCTAssertEqual(AmazonURLParser.extractASIN(from: url), "4088851306")
    }

    func test_gpProductPath_extractsASIN() {
        let url = URL(string: "https://www.amazon.co.jp/gp/product/4088851306")!
        XCTAssertEqual(AmazonURLParser.extractASIN(from: url), "4088851306")
    }

    func test_searchResultsPage_returnsNil() {
        let url = URL(string: "https://www.amazon.co.jp/s?k=ONE+PIECE")!
        XCTAssertNil(AmazonURLParser.extractASIN(from: url))
    }

    func test_unrelatedURL_returnsNil() {
        let url = URL(string: "https://example.com/")!
        XCTAssertNil(AmazonURLParser.extractASIN(from: url))
    }

    // MARK: - extractTitleHint（Kindle版ASIN等、ISBN変換に失敗した場合の紙の本再検索用）

    func test_extractTitleHint_titleImprintAuthorFormatSlug_returnsFirstSegment() {
        // 実機で確認したKindle版商品ページの実例
        let url = URL(string: "https://www.amazon.co.jp/プラチナデータ-幻冬舎文庫-東野圭吾-ebook/dp/B0872SGFKK")!
        XCTAssertEqual(AmazonURLParser.extractTitleHint(from: url), "プラチナデータ")
    }

    func test_extractTitleHint_noSlugBeforeDp_returnsNil() {
        let url = URL(string: "https://www.amazon.co.jp/dp/4088851306")!
        XCTAssertNil(AmazonURLParser.extractTitleHint(from: url))
    }

    func test_extractTitleHint_gpProductPath_returnsNil() {
        // gp/product形式にはタイトルスラグが付かないため、手掛かりとして使えない
        let url = URL(string: "https://www.amazon.co.jp/gp/product/4088851306")!
        XCTAssertNil(AmazonURLParser.extractTitleHint(from: url))
    }
}
