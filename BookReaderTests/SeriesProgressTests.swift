import XCTest
@testable import BookReader

final class SeriesProgressTests: XCTestCase {
    private func makeSeries(
        ownedVolumes: [Int],
        missingVolumes: [Int]?,
        completionRate: Double?
    ) -> SeriesProgress {
        SeriesProgress(
            seriesKey: "test",
            seriesName: "テスト",
            ownedVolumes: ownedVolumes,
            missingVolumes: missingVolumes,
            completionRate: completionRate,
            nextVolumeToBuy: nil,
            nextVolumeISBN: nil,
            volumes: []
        )
    }

    /// 積み上げ式進捗バーの分母として使う既刊総数（所持済み＋未所持）。
    func test_totalVolumes_knownCompletion_sumsOwnedAndMissing() {
        let series = makeSeries(ownedVolumes: [1, 2, 3], missingVolumes: [4, 5], completionRate: 0.6)
        XCTAssertEqual(series.totalVolumes, 5)
    }

    func test_totalVolumes_unknownCompletion_returnsNil() {
        let series = makeSeries(ownedVolumes: [1, 2], missingVolumes: nil, completionRate: nil)
        XCTAssertNil(series.totalVolumes)
    }
}
