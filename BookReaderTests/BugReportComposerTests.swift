import XCTest
@testable import BookReader

final class BugReportComposerTests: XCTestCase {
    func test_reportForBook_includesTitleSeriesVolumeAndISBN() {
        let book = Book(
            id: UUID(),
            isbn: "9784088851303",
            title: "ONE PIECE 115",
            seriesName: "ONE PIECE",
            seriesKey: "onepiece",
            volumeNumber: 115,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            registeredAt: Date(),
            lastOpenedAt: nil,
            metadataFetched: true
        )

        let report = BugReportComposer.report(for: book)

        XCTAssertTrue(report.subject.contains("ONE PIECE 115"))
        XCTAssertTrue(report.body.contains("タイトル: ONE PIECE 115"))
        XCTAssertTrue(report.body.contains("シリーズ名: ONE PIECE"))
        XCTAssertTrue(report.body.contains("巻数: 115"))
        XCTAssertTrue(report.body.contains("ISBN: 9784088851303"))
    }

    func test_reportForBook_omitsMissingOptionalFields() {
        let book = Book(
            id: UUID(),
            isbn: nil,
            title: "三体",
            seriesName: nil,
            seriesKey: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            registeredAt: Date(),
            lastOpenedAt: nil,
            metadataFetched: true
        )

        let report = BugReportComposer.report(for: book)

        XCTAssertFalse(report.body.contains("シリーズ名:"))
        XCTAssertFalse(report.body.contains("巻数:"))
        XCTAssertFalse(report.body.contains("ISBN:"))
    }

    func test_reportForSeries_includesOwnedAndMissingVolumes() {
        let series = SeriesProgress(
            seriesKey: "onepiece",
            seriesName: "ONE PIECE",
            ownedVolumes: [1, 3, 4],
            missingVolumes: [2],
            completionRate: 0.75,
            nextVolumeToBuy: 2,
            nextVolumeISBN: nil,
            volumes: []
        )

        let report = BugReportComposer.report(for: series)

        XCTAssertTrue(report.subject.contains("ONE PIECE"))
        XCTAssertTrue(report.body.contains("完結率: 75%"))
        XCTAssertTrue(report.body.contains("所持巻数: 3巻"))
        XCTAssertTrue(report.body.contains("所持している巻: 1, 3, 4"))
        XCTAssertTrue(report.body.contains("未所持の巻: 2"))
    }

    func test_reportForSeries_unknownCompletionRate_showsUnknown() {
        let series = SeriesProgress(
            seriesKey: "unknown",
            seriesName: "不明シリーズ",
            ownedVolumes: [1],
            missingVolumes: nil,
            completionRate: nil,
            nextVolumeToBuy: nil,
            nextVolumeISBN: nil,
            volumes: []
        )

        let report = BugReportComposer.report(for: series)

        XCTAssertTrue(report.body.contains("既刊数: 不明"))
        XCTAssertFalse(report.body.contains("未所持の巻:"))
    }
}
