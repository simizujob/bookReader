import XCTest
@testable import BookReader

final class BookMetadataTests: XCTestCase {
    func test_resolvedSeriesInfo_prefersStructuredFieldsWhenPresent() {
        let metadata = BookMetadata(title: "Hunter×hunter 5", seriesName: "Hunter×hunter", volumeNumber: 5)
        let resolved = metadata.resolvedSeriesInfo
        XCTAssertEqual(resolved.seriesName, "Hunter×hunter")
        XCTAssertEqual(resolved.volumeNumber, 5)
    }

    func test_resolvedSeriesInfo_fallsBackToTitleParserWhenStructuredFieldsMissing() {
        let metadata = BookMetadata(title: "鬼滅の刃 19")
        let resolved = metadata.resolvedSeriesInfo
        XCTAssertEqual(resolved.seriesName, "鬼滅の刃")
        XCTAssertEqual(resolved.volumeNumber, 19)
    }

    func test_resolvedSeriesInfo_standaloneBookWithoutVolumePattern_returnsNil() {
        let metadata = BookMetadata(title: "三体")
        let resolved = metadata.resolvedSeriesInfo
        XCTAssertNil(resolved.seriesName)
        XCTAssertNil(resolved.volumeNumber)
    }
}
