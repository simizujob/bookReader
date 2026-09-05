import XCTest
@testable import BookReader

final class CompositeBookMetadataServiceTests: XCTestCase {
    private final class StubSource: BookMetadataFetching {
        var metadata: BookMetadata?
        var seriesVolumeCount: SeriesVolumeCountResult?
        private(set) var fetchMetadataCallCount = 0

        func fetchMetadata(isbn: String) async throws -> BookMetadata {
            fetchMetadataCallCount += 1
            guard let metadata else { throw BookMetadataError.notFound }
            return metadata
        }

        func fetchSeriesVolumeCount(seriesName: String) async throws -> SeriesVolumeCountResult? {
            seriesVolumeCount
        }
    }

    func test_fetchMetadata_firstSourceSucceeds_usesResultWithoutCallingLaterSourcesWhenCoverPresent() async throws {
        let first = StubSource()
        first.metadata = BookMetadata(title: "NDLのタイトル", coverImageURL: "https://example.com/cover.jpg")
        let second = StubSource()
        second.metadata = BookMetadata(title: "openBDのタイトル", coverImageURL: nil)

        let service = CompositeBookMetadataService(sources: [first, second])
        let result = try await service.fetchMetadata(isbn: "9784081135684")

        XCTAssertEqual(result.title, "NDLのタイトル")
        XCTAssertEqual(second.fetchMetadataCallCount, 0, "最初のソースが表紙込みで成功した場合、後続は呼ばれないこと")
    }

    /// 実際のユースケース: NDL Searchはタイトル・巻数は強いが表紙画像を持たない。
    /// 表紙が無い場合は後続のソース（openBD）にも問い合わせ、表紙だけ補完する。
    func test_fetchMetadata_firstSourceHasNoCover_mergesCoverFromNextSource() async throws {
        let ndl = StubSource()
        ndl.metadata = BookMetadata(title: "Hunter×hunter 5", coverImageURL: nil, seriesName: "Hunter×hunter", volumeNumber: 5)
        let openBD = StubSource()
        openBD.metadata = BookMetadata(title: "別のタイトル表記", coverImageURL: "https://example.com/cover.jpg")

        let service = CompositeBookMetadataService(sources: [ndl, openBD])
        let result = try await service.fetchMetadata(isbn: "9784081135684")

        XCTAssertEqual(result.title, "Hunter×hunter 5", "タイトル・シリーズ情報は最初に成功したソース（NDL）を優先する")
        XCTAssertEqual(result.seriesName, "Hunter×hunter")
        XCTAssertEqual(result.volumeNumber, 5)
        XCTAssertEqual(result.coverImageURL, "https://example.com/cover.jpg", "表紙のみ後続ソースから補完する")
    }

    func test_fetchMetadata_firstSourceFails_fallsBackToNextSource() async throws {
        let first = StubSource() // metadata未設定 = notFound
        let second = StubSource()
        second.metadata = BookMetadata(title: "openBDのタイトル")

        let service = CompositeBookMetadataService(sources: [first, second])
        let result = try await service.fetchMetadata(isbn: "9784785982737")

        XCTAssertEqual(result.title, "openBDのタイトル")
    }

    func test_fetchMetadata_allSourcesFail_throws() async {
        let service = CompositeBookMetadataService(sources: [StubSource(), StubSource()])

        do {
            _ = try await service.fetchMetadata(isbn: "9789999999999")
            XCTFail("全ソースが失敗した場合はエラーを投げるべき")
        } catch {
            // 期待通り
        }
    }

    func test_fetchSeriesVolumeCount_usesFirstSourceThatHasAValue() async throws {
        let first = StubSource()
        let second = StubSource()
        second.seriesVolumeCount = SeriesVolumeCountResult(total: 20, isbnsByVolume: [:])

        let service = CompositeBookMetadataService(sources: [first, second])
        let result = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")

        XCTAssertEqual(result?.total, 20)
    }
}
