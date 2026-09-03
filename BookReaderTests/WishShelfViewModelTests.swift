import XCTest
@testable import BookReader

@MainActor
final class WishShelfViewModelTests: XCTestCase {
    private struct StubCalculator: SeriesProgressCalculating {
        let result: [SeriesProgress]
        func calculateAll() throws -> [SeriesProgress] { result }
    }

    func test_onAppear_populatesSeriesCards() {
        let progress = SeriesProgress(
            seriesKey: "sanhti", seriesName: "三体", ownedVolumes: [1],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: 2, nextVolumeISBN: nil
        )
        let viewModel = WishShelfViewModel(calculator: StubCalculator(result: [progress]))
        viewModel.onAppear()
        XCTAssertEqual(viewModel.seriesCards, [progress])
    }

    func test_openStoreSearch_usesISBNWhenAvailable() {
        let progress = SeriesProgress(
            seriesKey: "onipiece", seriesName: "鬼滅の刃", ownedVolumes: [1],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: 2, nextVolumeISBN: "9784041031400"
        )
        let viewModel = WishShelfViewModel(calculator: StubCalculator(result: [progress]))
        let url = viewModel.openStoreSearch(for: progress)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "k" }?.value, "9784041031400")
    }

    func test_openStoreSearch_fallsBackToKeywordsWhenISBNUnknown() {
        let progress = SeriesProgress(
            seriesKey: "shintaino", seriesName: "進撃の巨人", ownedVolumes: [1],
            missingVolumes: nil, completionRate: nil, nextVolumeToBuy: 2, nextVolumeISBN: nil
        )
        let viewModel = WishShelfViewModel(calculator: StubCalculator(result: [progress]))
        let url = viewModel.openStoreSearch(for: progress)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "k" }?.value, "進撃の巨人 2巻")
    }
}
