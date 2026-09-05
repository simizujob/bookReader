import XCTest
@testable import BookReader

final class OpenLibraryServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.responseProvider = nil
        super.tearDown()
    }

    /// 回帰テスト: search.jsonの"numFound"はシリーズ名の自由文字列検索のヒット総数であり、
    /// 既刊総数ではない（実際に「Hunter×hunter」で検索すると無関係な文献を含め5万件超がヒットする）。
    /// これをそのまま既刊総数として返すと、全巻自動登録（SeriesVolumeCountRefreshService）が
    /// 暴走して大量の偽レコードを作ってしまう不具合があったため、常にnilを返すことを確認する。
    func test_fetchSeriesVolumeCount_neverTrustsNumFoundAsVolumeCount() async throws {
        StubURLProtocol.responseProvider = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"numFound": 57799, "docs": []}"#
            return (json.data(using: .utf8)!, response)
        }
        let service = OpenLibraryService(session: StubURLProtocol.makeSession())

        let count = try await service.fetchSeriesVolumeCount(seriesName: "Hunter×hunter")
        XCTAssertNil(count, "自由文字列検索のヒット件数を既刊総数として採用してはならない")
    }
}
