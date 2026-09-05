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
}
