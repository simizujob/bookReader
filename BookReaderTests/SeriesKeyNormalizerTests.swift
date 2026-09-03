import XCTest
@testable import BookReader

final class SeriesKeyNormalizerTests: XCTestCase {
    func test_fullwidthAndHalfwidthVariants_normalizeToSameKey() {
        let a = SeriesKeyNormalizer.normalize("鬼滅の刃")
        let b = SeriesKeyNormalizer.normalize("鬼滅の刃　")
        XCTAssertEqual(a, b)
    }

    func test_trailingVolumeNumberPatterns_areStripped() {
        let base = SeriesKeyNormalizer.normalize("鬼滅の刃")
        XCTAssertEqual(SeriesKeyNormalizer.normalize("鬼滅の刃(19)"), base)
        XCTAssertEqual(SeriesKeyNormalizer.normalize("鬼滅の刃19"), base)
        XCTAssertEqual(SeriesKeyNormalizer.normalize("鬼滅の刃第19巻"), base)
    }

    func test_whitespaceVariants_normalizeToSameKey() {
        let a = SeriesKeyNormalizer.normalize("進撃の巨人")
        let b = SeriesKeyNormalizer.normalize("進撃の 巨人")
        XCTAssertEqual(a, b)
    }

    func test_caseInsensitive() {
        XCTAssertEqual(SeriesKeyNormalizer.normalize("ABC"), SeriesKeyNormalizer.normalize("abc"))
    }
}
