import XCTest
@testable import BookReader

final class TitleParserTests: XCTestCase {
    func test_seriesWithSpaceVolume_parsesSeriesAndVolume() {
        let result = TitleParser.parse("鬼滅の刃 19")
        XCTAssertEqual(result.seriesName, "鬼滅の刃")
        XCTAssertEqual(result.volumeNumber, 19)
    }

    func test_seriesWithParenVolume_parsesSeriesAndVolume() {
        let result = TitleParser.parse("鬼滅の刃(19)")
        XCTAssertEqual(result.seriesName, "鬼滅の刃")
        XCTAssertEqual(result.volumeNumber, 19)
    }

    func test_seriesWithKanjiVolume_parsesSeriesAndVolume() {
        let result = TitleParser.parse("鬼滅の刃 第19巻")
        XCTAssertEqual(result.seriesName, "鬼滅の刃")
        XCTAssertEqual(result.volumeNumber, 19)
    }

    func test_seriesWithVolAbbreviation_parsesSeriesAndVolume() {
        let result = TitleParser.parse("Kimetsu no Yaiba Vol.19")
        XCTAssertEqual(result.seriesName, "Kimetsu no Yaiba")
        XCTAssertEqual(result.volumeNumber, 19)
    }

    func test_singleVolumeBookWithoutVolumePattern_returnsNilSeriesAndVolume() {
        let result = TitleParser.parse("三体")
        XCTAssertNil(result.seriesName)
        XCTAssertNil(result.volumeNumber)
    }

    func test_titleFieldAlwaysReturnsTrimmedInput() {
        let result = TitleParser.parse("  三体  ")
        XCTAssertEqual(result.title, "三体")
    }
}
