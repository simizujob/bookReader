import XCTest
@testable import BookReader

final class UnifiedStatusTests: XCTestCase {
    func test_resolve_wishlist_isAlwaysUnpurchasedRegardlessOfReadStatus() {
        XCTAssertEqual(UnifiedStatus.resolve(status: .wishlist, readStatus: .unread), .wishlist)
        XCTAssertEqual(UnifiedStatus.resolve(status: .wishlist, readStatus: .finished), .wishlist)
    }

    func test_resolve_owned_mapsReadStatusDirectly() {
        XCTAssertEqual(UnifiedStatus.resolve(status: .owned, readStatus: .unread), .unread)
        XCTAssertEqual(UnifiedStatus.resolve(status: .owned, readStatus: .reading), .reading)
        XCTAssertEqual(UnifiedStatus.resolve(status: .owned, readStatus: .finished), .finished)
    }

    func test_bookStatusPair_roundTripsThroughResolve() {
        for status in UnifiedStatus.allCases {
            let pair = status.bookStatusPair
            XCTAssertEqual(UnifiedStatus.resolve(status: pair.status, readStatus: pair.readStatus), status)
        }
    }

    func test_book_unifiedStatus_reflectsUnderlyingFields() {
        let book = Book(
            id: UUID(), isbn: nil, title: "三体", seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: .owned, readStatus: .reading,
            registeredAt: Date(), lastOpenedAt: nil, metadataFetched: true
        )
        XCTAssertEqual(book.unifiedStatus, .reading)
    }

    func test_ordering_wishlistIsLowestFinishedIsHighest() {
        XCTAssertLessThan(UnifiedStatus.wishlist, UnifiedStatus.unread)
        XCTAssertLessThan(UnifiedStatus.unread, UnifiedStatus.reading)
        XCTAssertLessThan(UnifiedStatus.reading, UnifiedStatus.finished)
    }
}
