import XCTest
@testable import BookReader

final class OpenBDServiceTests: XCTestCase {
    /// 実際にopenBDから取得した応答（2026-09-04時点、ISBN 9784785982737）を固定データとして使用する。
    /// このISBNはOpen Libraryには存在しない（{}が返る）が、openBDには存在することを
    /// 事前にcurlで確認済み。日本の書籍に対するopenBD優先方針の正しさを裏付けるテスト。
    private static let foundResponseJSON = """
    [{"summary":{"isbn":"9784785982737","title":"みんなの食卓　わたしのおにぎり","volume":"","series":"ぐる漫","publisher":"少年画報社","pubdate":"","cover":"","author":"アンソロジー"}}]
    """

    private static let notFoundResponseJSON = "[null]"

    private func makeService(json: String, statusCode: Int = 200) -> OpenBDService {
        StubURLProtocol.responseProvider = { url in
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (json.data(using: .utf8)!, response)
        }
        return OpenBDService(session: StubURLProtocol.makeSession())
    }

    override func tearDown() {
        StubURLProtocol.responseProvider = nil
        super.tearDown()
    }

    func test_fetchMetadata_realWorldFoundResponse_parsesTitle() async throws {
        let service = makeService(json: Self.foundResponseJSON)
        let metadata = try await service.fetchMetadata(isbn: "9784785982737")
        XCTAssertEqual(metadata.title, "みんなの食卓　わたしのおにぎり")
        XCTAssertNil(metadata.coverImageURL, "この実データでは表紙URLが空文字のためnilになること")
        XCTAssertEqual(metadata.seriesName, "ぐる漫")
        XCTAssertNil(metadata.volumeNumber, "この実データではvolumeが空文字のためnilになること")
    }

    func test_fetchMetadata_seriesAndVolumePresent_areParsed() async throws {
        let json = """
        [{"summary":{"isbn":"9784088725093","title":"ONE PIECE","volume":"1","series":"ONE PIECE","cover":""}}]
        """
        let service = makeService(json: json)
        let metadata = try await service.fetchMetadata(isbn: "9784088725093")
        XCTAssertEqual(metadata.seriesName, "ONE PIECE")
        XCTAssertEqual(metadata.volumeNumber, 1)
    }

    func test_fetchMetadata_notFoundResponse_throwsNotFound() async throws {
        let service = makeService(json: Self.notFoundResponseJSON)
        do {
            _ = try await service.fetchMetadata(isbn: "9780000000000")
            XCTFail("notFoundが投げられるべき")
        } catch let error as OpenBDError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_fetchMetadata_coverURLPresent_isReturned() async throws {
        let json = """
        [{"summary":{"isbn":"9784088725093","title":"One piece 巻1","cover":"https://cover.example.com/9784088725093.jpg"}}]
        """
        let service = makeService(json: json)
        let metadata = try await service.fetchMetadata(isbn: "9784088725093")
        XCTAssertEqual(metadata.coverImageURL, "https://cover.example.com/9784088725093.jpg")
    }
}
