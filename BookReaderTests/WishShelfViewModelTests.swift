import XCTest
@testable import BookReader

@MainActor
final class WishShelfViewModelTests: XCTestCase {
    private struct StubCalculator: SeriesProgressCalculating {
        var result: [SeriesProgress] = []
        var standalone: [Book] = []
        func calculateAll() throws -> [SeriesProgress] { result }
        func standaloneWishlistBooks() throws -> [Book] { standalone }
        func seriesKeysNeedingRefresh() throws -> [String] { [] }
    }

    private func makeBook(title: String, isbn: String? = "9789999999999") -> Book {
        Book(
            id: UUID(), isbn: isbn, title: title, seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: .wishlist, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: false
        )
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

    /// 回帰テスト: 「買う前チェック」から「気になるリストへ」で追加した、
    /// シリーズ名が未確定の単発の本が気になる本棚から消えないこと（不具合の再発防止）。
    func test_onAppear_populatesStandaloneWishlistBooks() {
        let book = makeBook(title: "ISBN: 9789999999999")
        let viewModel = WishShelfViewModel(calculator: StubCalculator(standalone: [book]))
        viewModel.onAppear()
        XCTAssertEqual(viewModel.standaloneBooks, [book])
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

    func test_openStoreSearchForBook_usesISBNWhenAvailable() {
        let book = makeBook(title: "三体", isbn: "9781111111111")
        let viewModel = WishShelfViewModel(calculator: StubCalculator())
        let url = viewModel.openStoreSearch(for: book)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "k" }?.value, "9781111111111")
    }

    func test_openStoreSearchForBook_fallsBackToTitleWhenISBNUnknown() {
        let book = makeBook(title: "三体", isbn: nil)
        let viewModel = WishShelfViewModel(calculator: StubCalculator())
        let url = viewModel.openStoreSearch(for: book)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "k" }?.value, "三体")
    }
}
