import XCTest
@testable import BookReader

final class ShelfItemTests: XCTestCase {
    private func makeBook(
        title: String = "三体",
        status: OwnershipStatus = .wishlist,
        readStatus: ReadStatus = .unread,
        registeredAt: Date = Date()
    ) -> Book {
        Book(
            id: UUID(), isbn: nil, title: title, seriesName: nil, seriesKey: nil,
            volumeNumber: nil, coverImageURL: nil, status: status, readStatus: readStatus,
            registeredAt: registeredAt, lastOpenedAt: nil, metadataFetched: true
        )
    }

    private func makeSeries(
        seriesName: String = "鬼滅の刃",
        volumes: [SeriesVolumeEntry]
    ) -> SeriesProgress {
        SeriesProgress(
            seriesKey: SeriesKeyNormalizer.normalize(seriesName),
            seriesName: seriesName,
            ownedVolumes: [],
            missingVolumes: nil,
            completionRate: nil,
            nextVolumeToBuy: nil,
            nextVolumeISBN: nil,
            volumes: volumes
        )
    }

    func test_sortTitle_usesBookTitleOrSeriesName() {
        let book = ShelfItem.book(makeBook(title: "禁忌の子"))
        let series = ShelfItem.series(makeSeries(seriesName: "鬼滅の刃", volumes: []))

        XCTAssertEqual(book.sortTitle, "禁忌の子")
        XCTAssertEqual(series.sortTitle, "鬼滅の刃")
    }

    func test_latestRegisteredAt_seriesUsesMostRecentVolume() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        let series = ShelfItem.series(makeSeries(volumes: [
            SeriesVolumeEntry(bookID: UUID(), volumeNumber: 1, unifiedStatus: .unread, registeredAt: older, displayLabel: "1巻"),
            SeriesVolumeEntry(bookID: UUID(), volumeNumber: 2, unifiedStatus: .unread, registeredAt: newer, displayLabel: "2巻")
        ]))

        XCTAssertEqual(series.latestRegisteredAt, newer)
    }

    /// シリーズのステータス代表値は、1巻でも読了していないシリーズを目立たせるため
    /// 最も進捗が浅い（未購入に近い）ステータスを採用する。
    func test_sortStatus_seriesUsesLeastProgressedVolume() {
        let series = ShelfItem.series(makeSeries(volumes: [
            SeriesVolumeEntry(bookID: UUID(), volumeNumber: 1, unifiedStatus: .finished, registeredAt: Date(), displayLabel: "1巻"),
            SeriesVolumeEntry(bookID: UUID(), volumeNumber: 2, unifiedStatus: .unread, registeredAt: Date(), displayLabel: "2巻")
        ]))

        XCTAssertEqual(series.sortStatus, .unread)
    }

    func test_matches_isCaseInsensitiveSubstringMatch() {
        let item = ShelfItem.book(makeBook(title: "Hunter×hunter 5"))

        XCTAssertTrue(item.matches(searchText: "hunter"))
        XCTAssertTrue(item.matches(searchText: "5"))
        XCTAssertFalse(item.matches(searchText: "三体"))
    }

    func test_sortOption_newest_ordersByLatestRegisteredAtDescending() {
        let older = ShelfItem.book(makeBook(title: "古い本", registeredAt: Date(timeIntervalSince1970: 1000)))
        let newer = ShelfItem.book(makeBook(title: "新しい本", registeredAt: Date(timeIntervalSince1970: 2000)))

        let sorted = ShelfSortOption.newest.sorted([older, newer])
        XCTAssertEqual(sorted.map(\.sortTitle), ["新しい本", "古い本"])
    }

    func test_sortOption_title_ordersAlphabetically() {
        let b = ShelfItem.book(makeBook(title: "banana"))
        let a = ShelfItem.book(makeBook(title: "apple"))

        let sorted = ShelfSortOption.title.sorted([b, a])
        XCTAssertEqual(sorted.map(\.sortTitle), ["apple", "banana"])
    }

    func test_sortOption_status_ordersLeastProgressedFirst() {
        let finished = ShelfItem.book(makeBook(title: "読了済み", status: .owned, readStatus: .finished))
        let unread = ShelfItem.book(makeBook(title: "未読", status: .owned, readStatus: .unread))

        let sorted = ShelfSortOption.status.sorted([finished, unread])
        XCTAssertEqual(sorted.map(\.sortTitle), ["未読", "読了済み"])
    }
}
