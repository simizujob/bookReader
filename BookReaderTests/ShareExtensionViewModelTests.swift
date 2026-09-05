import XCTest
@testable import BookReader

private final class MockPaperEditionSearching: PaperEditionSearching {
    var isbnByTitleHint: [String: String] = [:]
    private(set) var searchedTitleHints: [String] = []

    func searchPaperEditionISBN(titleHint: String) async -> String? {
        searchedTitleHints.append(titleHint)
        return isbnByTitleHint[titleHint]
    }
}

@MainActor
final class ShareExtensionViewModelTests: XCTestCase {
    private let amazonURL = URL(string: "https://www.amazon.co.jp/dp/4088851307")!

    private func makeViewModel(
        repository: BookRepository = MockBookRepository(),
        metadataService: BookMetadataFetching = MockOpenLibraryService(),
        paperEditionSearching: PaperEditionSearching = MockPaperEditionSearching()
    ) -> ShareExtensionViewModel {
        ShareExtensionViewModel(
            bookRepository: repository,
            metadataService: metadataService,
            paperEditionSearching: paperEditionSearching
        )
    }

    func test_handle_ownedISBN_setsJudgedOwned() async throws {
        let repository = MockBookRepository()
        // 4088851307 は妥当なISBN-10チェックディジットを持ち、ISBN-13は9784088851303になる
        let book = Book(
            id: UUID(), isbn: "9784088851303", title: "ONE PIECE 1", seriesName: "ONE PIECE",
            seriesKey: "onepiece", volumeNumber: 1, coverImageURL: nil, status: .owned,
            readStatus: .unread, registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(book)
        let viewModel = makeViewModel(repository: repository)

        viewModel.handle(sharedURL: amazonURL)
        await viewModel.handleTask?.value

        XCTAssertEqual(viewModel.state, .judged(.owned(book)))
    }

    func test_handle_unrecognizedURL_setsUnrecognized() async throws {
        let viewModel = makeViewModel()

        viewModel.handle(sharedURL: URL(string: "https://www.amazon.co.jp/s?k=ONE+PIECE"))
        await viewModel.handleTask?.value

        XCTAssertEqual(viewModel.state, .unrecognized)
    }

    func test_handle_nilURL_setsUnrecognized() async throws {
        let viewModel = makeViewModel()

        viewModel.handle(sharedURL: nil)
        await viewModel.handleTask?.value

        XCTAssertEqual(viewModel.state, .unrecognized)
    }

    func test_handle_notOwnedISBN_showsFallbackTitleThenEnrichesFromMetadata() async throws {
        let metadataSource = MockOpenLibraryService()
        metadataSource.metadataByISBN["9784088851303"] = BookMetadata(
            title: "ONE PIECE 1", coverImageURL: "https://example.com/1.jpg", seriesName: "ONE PIECE", volumeNumber: 1
        )
        let viewModel = makeViewModel(metadataService: metadataSource)

        viewModel.handle(sharedURL: amazonURL)
        await viewModel.handleTask?.value
        XCTAssertEqual(viewModel.title, "ISBN: 9784088851303")

        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.title, "ONE PIECE 1")
        XCTAssertEqual(viewModel.coverImageURL, "https://example.com/1.jpg")
    }

    func test_addToWishlist_registersNotOwnedBook() async throws {
        let repository = MockBookRepository()
        let viewModel = makeViewModel(repository: repository)

        viewModel.handle(sharedURL: amazonURL)
        await viewModel.handleTask?.value
        await viewModel.enrichmentTask?.value
        viewModel.addToWishlist()

        XCTAssertEqual(repository.insertedDrafts.first?.isbn, "9784088851303")
        XCTAssertEqual(repository.insertedDrafts.first?.status, .wishlist)
    }

    func test_amazonReturnURL_includesTrackingTagForSameASIN() async throws {
        let viewModel = makeViewModel()

        viewModel.handle(sharedURL: amazonURL)
        await viewModel.handleTask?.value

        let components = URLComponents(url: try XCTUnwrap(viewModel.amazonReturnURL), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.path, "/dp/4088851307")
        XCTAssertNotNil(components.queryItems?.first { $0.name == "tag" }?.value)
    }

    func test_amazonReturnURL_unrecognizedURL_returnsNil() async throws {
        let viewModel = makeViewModel()

        viewModel.handle(sharedURL: URL(string: "https://example.com/"))
        await viewModel.handleTask?.value

        XCTAssertNil(viewModel.amazonReturnURL)
    }

    // MARK: - Kindle版ASIN（ISBN変換失敗）時の紙の本再検索フォールバック

    /// 回帰テスト: 実機で確認したケース（Kindle版商品ページのASIN "B0872SGFKK" はISBNとして
    /// 無効）。URLから推測したタイトルで紙の本の再検索を行い、高い類似度で見つかれば
    /// そちらのISBNで判定を続行する。
    func test_handle_kindleASIN_paperEditionFound_judgesUsingPaperISBN() async throws {
        let repository = MockBookRepository()
        let paperSearch = MockPaperEditionSearching()
        paperSearch.isbnByTitleHint["プラチナデータ"] = "9784344421064"
        let book = Book(
            id: UUID(), isbn: "9784344421064", title: "プラチナデータ", seriesName: nil,
            seriesKey: nil, volumeNumber: nil, coverImageURL: nil, status: .owned,
            readStatus: .unread, registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(book)
        let viewModel = makeViewModel(repository: repository, paperEditionSearching: paperSearch)

        let kindleURL = URL(string: "https://www.amazon.co.jp/プラチナデータ-幻冬舎文庫-東野圭吾-ebook/dp/B0872SGFKK")!
        viewModel.handle(sharedURL: kindleURL)
        await viewModel.handleTask?.value

        XCTAssertEqual(paperSearch.searchedTitleHints, ["プラチナデータ"])
        XCTAssertEqual(viewModel.state, .judged(.owned(book)))
    }

    /// 紙の本の再検索でも見つからない場合は、これまで通り.unrecognizedとして
    /// 「紙の商品ページを共有してください」等の案内を表示側に委ねる。
    func test_handle_kindleASIN_paperEditionNotFound_setsUnrecognized() async throws {
        let paperSearch = MockPaperEditionSearching() // 何も登録しない = 見つからない
        let viewModel = makeViewModel(paperEditionSearching: paperSearch)

        let kindleURL = URL(string: "https://www.amazon.co.jp/プラチナデータ-幻冬舎文庫-東野圭吾-ebook/dp/B0872SGFKK")!
        viewModel.handle(sharedURL: kindleURL)
        await viewModel.handleTask?.value

        XCTAssertEqual(viewModel.state, .unrecognized)
    }
}
