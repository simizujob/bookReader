import XCTest
@testable import BookReader

final class AffiliateLinkServiceTests: XCTestCase {
    private let service = AffiliateLinkService()

    func test_isbnSearchURL_includesTrackingTag() {
        let url = service.amazonSearchURL(isbn: "9784041031400")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(items["tag"], "taros0480x84e-22")
        XCTAssertEqual(items["k"], "9784041031400")
    }

    func test_keywordSearchURL_includesTrackingTag() {
        let url = service.amazonSearchURL(keywords: "鬼滅の刃 20巻")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(items["tag"], "taros0480x84e-22")
        XCTAssertEqual(items["k"], "鬼滅の刃 20巻")
    }

    func test_productURL_pointsToSameASINWithTrackingTag() {
        let url = service.amazonProductURL(asin: "4088851306")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.path, "/dp/4088851306")
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        XCTAssertEqual(items["tag"], "taros0480x84e-22")
    }

    func test_forcedToOpenInSafari_prependsXSafariScheme() {
        let url = URL(string: "https://www.amazon.co.jp/dp/4088851306?tag=taros0480x84e-22")!
        XCTAssertEqual(
            url.forcedToOpenInSafari.absoluteString,
            "x-safari-https://www.amazon.co.jp/dp/4088851306?tag=taros0480x84e-22"
        )
    }

    func test_forcedToOpenInSafari_nonHTTPSURL_returnsUnchanged() {
        let url = URL(string: "mailto:test@example.com")!
        XCTAssertEqual(url.forcedToOpenInSafari, url)
    }
}
