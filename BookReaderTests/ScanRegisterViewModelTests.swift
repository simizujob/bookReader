import XCTest
@testable import BookReader

@MainActor
final class ScanRegisterViewModelTests: XCTestCase {
    func test_register_newISBN_registersAsOwned() async throws {
        let repository = MockBookRepository()
        let metadataSource = MockOpenLibraryService()
        metadataSource.metadataByISBN["9784081135684"] = BookMetadata(
            title: "Hunter×hunter 5", seriesName: "Hunter×hunter", volumeNumber: 5
        )
        let viewModel = ScanRegisterViewModel(bookRepository: repository, metadataService: metadataSource)

        viewModel.register(isbn: "9784081135684")
        await viewModel.registrationTask?.value

        let draft = try XCTUnwrap(repository.insertedDrafts.first)
        XCTAssertEqual(draft.isbn, "9784081135684")
        XCTAssertEqual(draft.status, .owned)
        XCTAssertEqual(draft.seriesName, "Hunter×hunter")
        XCTAssertEqual(draft.volumeNumber, 5)
        XCTAssertEqual(viewModel.registerState, .result(.registered(try XCTUnwrap(repository.books.first))))
    }

    func test_register_metadataUnavailable_registersWithFallbackTitle() async throws {
        let repository = MockBookRepository()
        let viewModel = ScanRegisterViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.register(isbn: "9789999999999")
        await viewModel.registrationTask?.value

        let draft = try XCTUnwrap(repository.insertedDrafts.first)
        XCTAssertEqual(draft.title, "ISBN: 9789999999999")
        XCTAssertEqual(draft.status, .owned)
        XCTAssertFalse(draft.metadataFetched)
    }

    /// 回帰テスト: 既に「気になるリストへ」で登録済みの本をスキャンした場合、重複登録せず
    /// 既存レコードを購入済みへ更新すること。
    func test_register_existingWishlistBook_upgradesToOwnedInstadOfDuplicating() async throws {
        let repository = MockBookRepository()
        let existing = Book(
            id: UUID(), isbn: "9784081135684", title: "Hunter×hunter 5", seriesName: "Hunter×hunter",
            seriesKey: SeriesKeyNormalizer.normalize("Hunter×hunter"), volumeNumber: 5, coverImageURL: nil,
            status: .wishlist, readStatus: .unread, registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(existing)
        let viewModel = ScanRegisterViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.register(isbn: "9784081135684")
        await viewModel.registrationTask?.value

        XCTAssertTrue(repository.insertedDrafts.isEmpty, "重複登録しないこと")
        let updated = try XCTUnwrap(try repository.find(id: existing.id))
        XCTAssertEqual(updated.status, .owned)
        if case .result(.upgradedFromWishlist(let book)) = viewModel.registerState {
            XCTAssertEqual(book.id, existing.id)
        } else {
            XCTFail("upgradedFromWishlistになるべき: \(viewModel.registerState)")
        }
    }

    /// 回帰テスト: 既に購入済みの本を再スキャンした場合は何も変更せず、既に登録済みであることを示すこと。
    func test_register_existingOwnedBook_reportsAlreadyOwnedWithoutMutating() async throws {
        let repository = MockBookRepository()
        let existing = Book(
            id: UUID(), isbn: "9784081135684", title: "Hunter×hunter 5", seriesName: "Hunter×hunter",
            seriesKey: SeriesKeyNormalizer.normalize("Hunter×hunter"), volumeNumber: 5, coverImageURL: nil,
            status: .owned, readStatus: .reading, registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(existing)
        let viewModel = ScanRegisterViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.register(isbn: "9784081135684")
        await viewModel.registrationTask?.value

        XCTAssertTrue(repository.insertedDrafts.isEmpty)
        XCTAssertTrue(repository.updatedIDs.isEmpty, "既に購入済みなら更新も発生しないこと")
        XCTAssertEqual(viewModel.registerState, .result(.alreadyOwned(existing)))
    }

    /// 回帰テスト: 既刊数自動取得が作成したISBN未確定のプレースホルダーと同じ巻をスキャンした場合、
    /// 新規登録せずプレースホルダーを実データ（ISBN）で更新すること。
    func test_register_matchesAutoBackfilledPlaceholder_upgradesPlaceholderInPlace() async throws {
        let repository = MockBookRepository()
        let placeholder = Book(
            id: UUID(), isbn: nil, title: "Hunter×hunter 5", seriesName: "Hunter×hunter",
            seriesKey: SeriesKeyNormalizer.normalize("Hunter×hunter"), volumeNumber: 5, coverImageURL: nil,
            status: .wishlist, readStatus: .unread, registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        repository.seed(placeholder)
        let metadataSource = MockOpenLibraryService()
        metadataSource.metadataByISBN["9784081135684"] = BookMetadata(
            title: "Hunter×hunter 5", seriesName: "Hunter×hunter", volumeNumber: 5
        )
        let viewModel = ScanRegisterViewModel(bookRepository: repository, metadataService: metadataSource)

        viewModel.register(isbn: "9784081135684")
        await viewModel.registrationTask?.value

        XCTAssertTrue(repository.insertedDrafts.isEmpty, "重複登録せずプレースホルダーを更新すること")
        let updated = try XCTUnwrap(try repository.find(id: placeholder.id))
        XCTAssertEqual(updated.status, .owned)
        XCTAssertEqual(updated.isbn, "9784081135684")
    }

    /// カメラが同じ本を映し続けている間、同一ISBNの繰り返し検出で二重登録しないこと。
    func test_handleCapturedFrame_repeatedSameISBN_doesNotReprocess() async throws {
        let repository = MockBookRepository()
        let viewModel = ScanRegisterViewModel(bookRepository: repository, metadataService: MockOpenLibraryService())

        viewModel.register(isbn: "9789999999999")
        await viewModel.registrationTask?.value
        XCTAssertEqual(repository.books.count, 1)

        viewModel.register(isbn: "9789999999999")
        XCTAssertEqual(repository.books.count, 1, "同じISBNの間は再処理しないこと")
    }
}
