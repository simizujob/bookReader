import XCTest
@testable import BookReader

final class TitleMatcherTests: XCTestCase {
    func test_identicalTitles_similarityIsOne() {
        XCTAssertEqual(TitleMatcher.similarity("三体", "三体"), 1.0)
    }

    func test_completelyDifferentTitles_similarityIsNearZero() {
        let similarity = TitleMatcher.similarity("三体", "わたしを離さないで")
        XCTAssertLessThan(similarity, 0.3)
    }

    func test_punctuationVariants_meetHighConfidenceThreshold() {
        let similarity = TitleMatcher.similarity("鬼滅の刃(19)", "鬼滅の刃 19")
        XCTAssertGreaterThanOrEqual(similarity, 0.8)
    }

    func test_emptyString_returnsZero() {
        XCTAssertEqual(TitleMatcher.similarity("", "三体"), 0)
        XCTAssertEqual(TitleMatcher.similarity("三体", ""), 0)
    }
}
