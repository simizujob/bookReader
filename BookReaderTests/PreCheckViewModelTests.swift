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
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9784041031400")

        XCTAssertEqual(viewModel.scanState, .judged(.owned(book)))
    }

    /// 回帰テスト: 既に「気になるリストへ」で登録済み（未購入）の本をスキャンした場合、
    /// .notOwnedではなく専用の.wishlistedとして判定されること。
    func test_judge_wishlistedISBN_setsJudgedWishlisted() {
        let repository = MockBookRepository()
        let book = Book(
            id: UUID(), isbn: "9784041031400", title: "三体", seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: .wishlist, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(book)
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9784041031400")

        XCTAssertEqual(viewModel.scanState, .judged(.wishlisted(book)))
    }

    func test_judge_unknownISBN_immediatelyShowsFallbackTitleWithoutEnrichment() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

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
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.enrichedContext.title, "ISBN: 9789999999999")
        XCTAssertFalse(viewModel.enrichedContext.isResolvedFromAPI)
    }

    func test_addToWishlistAndContinueScanning_registersAsWishlistAndReturnsToScanning() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        viewModel.addToWishlistAndContinueScanning()

        XCTAssertEqual(repository.insertedDrafts.count, 1)
        XCTAssertEqual(repository.insertedDrafts.first?.status, .wishlist)
        XCTAssertEqual(repository.insertedDrafts.first?.isbn, "9789999999999")
        // 仕様変更: 登録ボタン押下でスキャン結果を消し、即座に次のスキャンへ戻ること
        XCTAssertEqual(viewModel.scanState, .scanning)
    }

    func test_addToWishlistAndContinueScanning_openLibraryHasNoData_registersWithFallbackTitleAndMetadataFetchedFalse() async throws {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        await viewModel.enrichmentTask?.value
        viewModel.addToWishlistAndContinueScanning()

        let draft = try XCTUnwrap(repository.insertedDrafts.first)
        XCTAssertEqual(draft.title, "ISBN: 9789999999999")
        XCTAssertNil(draft.seriesName)
        XCTAssertFalse(draft.metadataFetched, "未取得のまま登録された本は後でバックフィルされるようmetadataFetched=falseにする必要がある")
    }

    func test_addToWishlistAndContinueScanning_openLibraryResolves_parsesSeriesAndVolume() async throws {
        let repository = MockBookRepository()
        let openLibrary = MockOpenLibraryService()
        openLibrary.metadataByISBN["9782222222222"] = BookMetadata(title: "鬼滅の刃 20", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: openLibrary)
        viewModel.judge(isbn: "9782222222222")
        await viewModel.enrichmentTask?.value
        viewModel.addToWishlistAndContinueScanning()

        let draft = try XCTUnwrap(repository.insertedDrafts.first)
        XCTAssertEqual(draft.title, "鬼滅の刃 20")
        XCTAssertEqual(draft.seriesName, "鬼滅の刃")
        XCTAssertEqual(draft.volumeNumber, 20)
        XCTAssertTrue(draft.metadataFetched)
    }

    /// NDL Search等、シリーズ名・巻数を構造化フィールドで返すデータソースの場合は
    /// タイトル文字列の推定（TitleParser）を経由せず、構造化データをそのまま使うこと。
    func test_addToWishlistAndContinueScanning_structuredMetadata_usesStructuredSeriesInfoDirectly() async throws {
        let repository = MockBookRepository()
        let metadataSource = MockOpenLibraryService()
        metadataSource.metadataByISBN["9784081135684"] = BookMetadata(
            title: "Hunter×hunter 5",
            seriesName: "Hunter×hunter",
            volumeNumber: 5
        )

        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: metadataSource)
        viewModel.judge(isbn: "9784081135684")
        await viewModel.enrichmentTask?.value
        viewModel.addToWishlistAndContinueScanning()

        let draft = try XCTUnwrap(repository.insertedDrafts.first)
        XCTAssertEqual(draft.seriesName, "Hunter×hunter")
        XCTAssertEqual(draft.volumeNumber, 5)
    }

    /// 回帰テスト: 既刊数が判明したシリーズは未登録の巻をISBN未確定のプレースホルダーとして
    /// 自動登録している（SeriesVolumeCountRefreshService.backfillMissingVolumes）。その巻を
    /// 実際にスキャンした場合、新規登録して重複させるのではなく、プレースホルダーを
    /// 実データ（ISBN・表紙画像）で更新すること。
    func test_addToWishlistAndContinueScanning_matchesAutoBackfilledPlaceholder_updatesInsteadOfDuplicating() async throws {
        let repository = MockBookRepository()
        let placeholder = Book(
            id: UUID(), isbn: nil, title: "Hunter×hunter 5", seriesName: "Hunter×hunter",
            seriesKey: SeriesKeyNormalizer.normalize("Hunter×hunter"), volumeNumber: 5, coverImageURL: nil,
            status: .wishlist, readStatus: .unread, registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(placeholder)

        let metadataSource = MockOpenLibraryService()
        metadataSource.metadataByISBN["9784081135684"] = BookMetadata(
            title: "Hunter×hunter 5",
            coverImageURL: "https://example.com/cover.jpg",
            seriesName: "Hunter×hunter",
            volumeNumber: 5
        )
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: metadataSource)
        viewModel.judge(isbn: "9784081135684")
        await viewModel.enrichmentTask?.value
        viewModel.addToWishlistAndContinueScanning()

        XCTAssertTrue(repository.insertedDrafts.isEmpty, "プレースホルダーと同じ巻は新規登録せず更新すること")
        XCTAssertTrue(repository.updatedIDs.contains(placeholder.id))
        let updated = try XCTUnwrap(try repository.find(id: placeholder.id))
        XCTAssertEqual(updated.isbn, "9784081135684")
        XCTAssertEqual(updated.coverImageURL, "https://example.com/cover.jpg")
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
        openLibrary.metadataByISBN["9782222222222"] = BookMetadata(title: "三体", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: openLibrary)
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
        openLibrary.metadataByISBN["9782222222222"] = BookMetadata(title: "鬼滅の刃 20", coverImageURL: nil)

        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: openLibrary)
        viewModel.judge(isbn: "9782222222222")
        await viewModel.enrichmentTask?.value

        XCTAssertEqual(viewModel.enrichedContext.partialSeriesInfo?.ownedThrough, 19)
        XCTAssertEqual(viewModel.enrichedContext.partialSeriesInfo?.missingVolume, 20)
    }

    func test_addToWishlistAndContinueScanning_withoutPriorJudgment_doesNothing() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.addToWishlistAndContinueScanning()

        XCTAssertTrue(repository.insertedDrafts.isEmpty)
        XCTAssertEqual(viewModel.scanState, .scanning)
    }

    func test_skipAndContinueScanning_doesNotRegisterAndReturnsToScanning() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        viewModel.skipAndContinueScanning()

        XCTAssertTrue(repository.insertedDrafts.isEmpty, "スキップでは登録しないこと")
        XCTAssertEqual(viewModel.scanState, .scanning)
    }

    func test_continueScanning_fromOwnedResult_returnsToScanning() {
        let repository = MockBookRepository()
        let book = Book(
            id: UUID(), isbn: "9784041031400", title: "三体", seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: .owned, readStatus: .unread,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(book)
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9784041031400")
        viewModel.continueScanning()

        XCTAssertEqual(viewModel.scanState, .scanning)
    }

    /// 回帰テスト（仕様変更）: 判定結果を表示中は、ユーザーが次へ進むボタンを押すまで
    /// 新しいISBNの検出を無視すること。結果を確認せず次々スキャンされてしまうのを防ぐため。
    func test_onceJudged_ignoresNewISBNDetectionUntilContinueScanning() {
        let repository = MockBookRepository()
        let viewModel = PreCheckViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.judge(isbn: "9789999999999")
        XCTAssertEqual(viewModel.scanState, .judged(.notOwned(possibleEdition: nil)))

        // 判定結果を表示中に別の本のバーコードが検出されても無視される
        viewModel.judge(isbn: "9788888888888")
        XCTAssertEqual(viewModel.enrichedContext.title, "ISBN: 9789999999999", "次へボタンを押すまで結果表示は変わらないこと")

        // 次へ進むボタン相当の操作で初めて次のスキャンを受け付ける
        viewModel.continueScanning()
        XCTAssertEqual(viewModel.scanState, .scanning)

        viewModel.judge(isbn: "9788888888888")
        XCTAssertEqual(viewModel.enrichedContext.title, "ISBN: 9788888888888")
    }
}
