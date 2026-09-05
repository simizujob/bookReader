import XCTest
@testable import BookReader

@MainActor
final class ShareExtensionViewModelTests: XCTestCase {
    private let amazonURL = URL(string: "https://www.amazon.co.jp/dp/4088851307")!

    func test_handle_ownedISBN_setsJudgedOwned() {
        let repository = MockBookRepository()
        // 4088851307 は妥当なISBN-10チェックディジットを持ち、ISBN-13は9784088851303になる
        let book = Book(
            id: UUID(), isbn: "9784088851303", title: "ONE PIECE 1", seriesName: "ONE PIECE",
            seriesKey: "onepiece", volumeNumber: 1, coverImageURL: nil, status: .owned,
            readStatus: .unread, registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(book)
        let viewModel = ShareExtensionViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.handle(sharedURL: amazonURL)

        XCTAssertEqual(viewModel.state, .judged(.owned(book)))
    }

    func test_handle_unrecognizedURL_setsUnrecognized() {
        let repository = MockBookRepository()
        let viewModel = ShareExtensionViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.handle(sharedURL: URL(string: "https://www.amazon.co.jp/s?k=ONE+PIECE"))

        XCTAssertEqual(viewModel.state, .unrecognized)
    }

    func test_handle_nilURL_setsUnrecognized() {
        let repository = MockBookRepository()
        let viewModel = ShareExtensionViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.handle(sharedURL: nil)

        XCTAssertEqual(viewModel.state, .unrecognized)
    }

    func test_handle_notOwnedISBN_showsFallbackTitleThenEnrichesFromMetadata() async throws {
        let repository = MockBookRepository()
        let metadataSource = MockOpenLibraryService()
        metadataSource.metadataByISBN["9784088851303"] = BookMetadata(
            title: "ONE PIECE 1", coverImageURL: "https://example.com/1.jpg", seriesName: "ONE PIECE", volumeNumber: 1
        )
        let viewModel = ShareExtensionViewModel(bookRepository: repository, metadataService: metadataSource)

        viewModel.handle(sharedURL: amazonURL)
        XCTAssertEqual(viewModel.title, "ISBN: 9784088851303")

        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.title, "ONE PIECE 1")
        XCTAssertEqual(viewModel.coverImageURL, "https://example.com/1.jpg")
    }

    func test_addToWishlist_registersNotOwnedBook() async throws {
        let repository = MockBookRepository()
        let viewModel = ShareExtensionViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.handle(sharedURL: amazonURL)
        await viewModel.enrichmentTask?.value
        viewModel.addToWishlist()

        XCTAssertEqual(repository.insertedDrafts.first?.isbn, "9784088851303")
        XCTAssertEqual(repository.insertedDrafts.first?.status, .wishlist)
    }

    func test_amazonReturnURL_includesTrackingTagForSameASIN() {
        let repository = MockBookRepository()
        let viewModel = ShareExtensionViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.handle(sharedURL: amazonURL)

        let components = URLComponents(url: try! XCTUnwrap(viewModel.amazonReturnURL), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.path, "/dp/4088851307")
        XCTAssertNotNil(components.queryItems?.first { $0.name == "tag" }?.value)
    }

    func test_amazonReturnURL_unrecognizedURL_returnsNil() {
        let repository = MockBookRepository()
        let viewModel = ShareExtensionViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.handle(sharedURL: URL(string: "https://example.com/"))

        XCTAssertNil(viewModel.amazonReturnURL)
    }
}
