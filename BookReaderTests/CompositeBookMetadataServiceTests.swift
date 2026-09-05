import XCTest
@testable import BookReader

final class CompositeBookMetadataServiceTests: XCTestCase {
    private final class StubSource: BookMetadataFetching {
        var metadata: BookMetadata?
        var seriesVolumeCount: Int?
        private(set) var fetchMetadataCallCount = 0

        func fetchMetadata(isbn: String) async throws -> BookMetadata {
            fetchMetadataCallCount += 1
            guard let metadata else { throw OpenBDError.notFound }
            return metadata
        }

        func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
            seriesVolumeCount
        }
    }

    func test_fetchMetadata_primarySucceeds_usesResultWithoutCallingFallback() async throws {
        let primary = StubSource()
        primary.metadata = BookMetadata(title: "openBDのタイトル", coverImageURL: nil)
        let fallback = StubSource()
        fallback.metadata = BookMetadata(title: "Open Libraryのタイトル", coverImageURL: nil)

        let service = CompositeBookMetadataService(primary: primary, fallback: fallback)
        let result = try await service.fetchMetadata(isbn: "9784785982737")

        XCTAssertEqual(result.title, "openBDのタイトル")
        XCTAssertEqual(fallback.fetchMetadataCallCount, 0, "primaryが成功した場合fallbackは呼ばれないこと")
    }

    func test_fetchMetadata_primaryFails_fallsBackToSecondSource() async throws {
        let primary = StubSource() // metadata未設定 = notFound
        let fallback = StubSource()
        fallback.metadata = BookMetadata(title: "Open Libraryのタイトル", coverImageURL: nil)

        let service = CompositeBookMetadataService(primary: primary, fallback: fallback)
        let result = try await service.fetchMetadata(isbn: "9784785982737")

        XCTAssertEqual(result.title, "Open Libraryのタイトル")
    }

    func test_fetchMetadata_bothFail_throws() async {
        let primary = StubSource()
        let fallback = StubSource()
        let service = CompositeBookMetadataService(primary: primary, fallback: fallback)

        do {
            _ = try await service.fetchMetadata(isbn: "9789999999999")
            XCTFail("両方失敗した場合はエラーを投げるべき")
        } catch {
            // 期待通り
        }
    }

    func test_fetchSeriesVolumeCount_delegatesToFallbackOnly() async throws {
        let primary = StubSource()
        let fallback = StubSource()
        fallback.seriesVolumeCount = 20

        let service = CompositeBookMetadataService(primary: primary, fallback: fallback)
        let count = try await service.fetchSeriesVolumeCount(seriesName: "鬼滅の刃")

        XCTAssertEqual(count, 20)
    }
}
