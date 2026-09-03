import XCTest
@testable import BookReader

@MainActor
final class PreCheckViewModelTests: XCTestCase {
    func test_judge_ownedISBN_setsJudgedOwned() {
        let repository = MockBookRepository()
        let book = Book(
            id: UUID(), isbn: "9784041031400", title: "三体", seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: .owned, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(book)
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9784041031400")

        XCTAssertEqual(viewModel.scanState, .judged(.owned(book)))
    }

    func test_judge_unknownISBN_immediatelyShowsFallbackTitleWithoutEnrichment() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")

        XCTAssertEqual(viewModel.scanState, .judged(.notOwned(possibleEdition: nil)))
        // バーコード単独ではタイトルが未知のため、この時点ではeditionWarning等は設定されない
        XCTAssertNil(viewModel.enrichedContext.editionWarning)
        // Open Libraryの応答を待たず、ISBNそのものが即座に仮タイトルとして表示される
        // （画面下部に「スキャンした本」が必ず表示されるようにするための対応）
        XCTAssertEqual(viewModel.enrichedContext.title, "ISBN: 9789999999999")
        XCTAssertFalse(viewModel.enrichedContext.isResolvedFromAPI)
    }

    func test_judge_unknownISBN_openLibraryHasNoData_keepsFallbackTitleAfterEnrichment() async throws {
        // Open Libraryが日本の書籍を収載しておらずnotFoundになるケース
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.enrichedContext.title, "ISBN: 9789999999999")
        XCTAssertFalse(viewModel.enrichedContext.isResolvedFromAPI)
    }

    func test_addCurrentResultToWishlist_openLibraryHasNoData_registersWithFallbackTitleAndMetadataFetchedFalse() async throws {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        await viewModel.enrichmentTask?.value
        viewModel.addCurrentResultToWishlist()

        let draft = try XCTUnwrap(repository.insertedDrafts.first)
        XCTAssertEqual(draft.title, "ISBN: 9789999999999")
        XCTAssertNil(draft.seriesName)
        XCTAssertFalse(draft.metadataFetched, "未取得のまま登録された本は後でバックフィルされるようmetadataFetched=falseにする必要がある")
    }

    func test_addCurrentResultToWishlist_openLibraryResolves_parsesSeriesAndVolume() async throws {
        let repository = MockBookRepository()
        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9782222222222"] = OpenLibraryBookMetadata(title: "鬼滅の刃 20", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: openLibrary)
        viewModel.judge(isbn: "9782222222222")
        await viewModel.enrichmentTask?.value
        viewModel.addCurrentResultToWishlist()

        let draft = try XCTUnwrap(repository.insertedDrafts.first)
        XCTAssertEqual(draft.title, "鬼滅の刃 20")
        XCTAssertEqual(draft.seriesName, "鬼滅の刃")
        XCTAssertEqual(draft.volumeNumber, 20)
        XCTAssertTrue(draft.metadataFetched)
    }

    func test_judge_unknownISBN_afterMetadataResolves_detectsEditionWarning() async throws {
        let repository = MockBookRepository()
        // 単行本を所持している状態で、文庫版（別ISBN）をスキャンするケース
        try repository.insert(BookDraft(
            isbn: "9781111111111",
            title: "三体",
            seriesName: nil,
            volumeNumber: nil,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))

        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9782222222222"] = OpenLibraryBookMetadata(title: "三体", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: openLibrary)
        viewModel.judge(isbn: "9782222222222")
        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.enrichedContext.editionWarning?.matchedBook.isbn, "9781111111111")
    }

    func test_judge_unknownISBN_afterMetadataResolves_detectsPartialSeriesOwnership() async throws {
        let repository = MockBookRepository()
        try repository.insert(BookDraft(
            isbn: "9781111111111",
            title: "鬼滅の刃 19",
            seriesName: "鬼滅の刃",
            volumeNumber: 19,
            coverImageURL: nil,
            status: .owned,
            readStatus: .unread,
            metadataFetched: true
        ))

        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9782222222222"] = OpenLibraryBookMetadata(title: "鬼滅の刃 20", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: openLibrary)
        viewModel.judge(isbn: "9782222222222")
        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.enrichedContext.partialSeriesInfo?.ownedThrough, 19)
        XCTAssertEqual(viewModel.enrichedContext.partialSeriesInfo?.missingVolume, 20)
    }

    func test_addCurrentResultToWishlist_registersAsWishlist() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        viewModel.addCurrentResultToWishlist()

        XCTAssertEqual(repository.insertedDrafts.count, 1)
        XCTAssertEqual(repository.insertedDrafts.first?.status, .wishlist)
        XCTAssertEqual(repository.insertedDrafts.first?.isbn, "9789999999999")
    }

    func test_addCurrentResultToWishlist_setsDidAddToWishlistForUIFeedback() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        XCTAssertFalse(viewModel.didAddToWishlist)

        viewModel.addCurrentResultToWishlist()
        XCTAssertTrue(viewModel.didAddToWishlist)
    }

    func test_addCurrentResultToWishlist_withoutPriorJudgment_doesNothing() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.addCurrentResultToWishlist()

        XCTAssertTrue(repository.insertedDrafts.isEmpty)
        XCTAssertFalse(viewModel.didAddToWishlist)
    }

    /// 不具合修正の回帰テスト: カメラが同じ本を映し続けている間、同一ISBNが繰り返し検出されても
    /// enrichedContextやdidAddToWishlistが再リセットされず、ユーザー操作（追加ボタンのタップ）の
    /// 結果が上書きされないこと。
    func test_repeatedSameISBNDetection_doesNotResetStateOrLoseWishlistFeedback() async throws {
        let repository = MockBookRepository()
        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9789999999999"] = OpenLibraryBookMetadata(title: "三体", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: openLibrary)

        viewModel.judge(isbn: "9789999999999")
        await viewModel.enrichmentTask?.value
        viewModel.addCurrentResultToWishlist()
        XCTAssertTrue(viewModel.didAddToWishlist)

        // カメラが同じ本を映し続け、同一ISBNが再度検出されるシミュレーション
        viewModel.judge(isbn: "9789999999999")

        XCTAssertTrue(viewModel.didAddToWishlist, "同一ISBNの再検出で追加済みフィードバックが消えてはいけない")
        XCTAssertEqual(viewModel.enrichedContext.title, "三体", "同一ISBNの再検出でスキャン結果表示が消えてはいけない")
        XCTAssertEqual(repository.insertedDrafts.count, 1, "同一ISBNの再検出で重複登録されてはいけない")
    }

    func test_differentISBNDetection_resetsStateAndWishlistFeedback() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, openLibraryService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        viewModel.addCurrentResultToWishlist()
        XCTAssertTrue(viewModel.didAddToWishlist)

        viewModel.judge(isbn: "9788888888888")

        XCTAssertFalse(viewModel.didAddToWishlist)
    }
}
