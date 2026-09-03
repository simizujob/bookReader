import XCTest
@testable import BookReader

final class BarcodeScanServiceTests: XCTestCase {
    func test_isbn13WithPrefix978_isValid() {
        XCTAssertTrue(BarcodeScanService.isValidISBN13("9784041031400"))
    }

    func test_isbn13WithPrefix979_isValid() {
        XCTAssertTrue(BarcodeScanService.isValidISBN13("9791234567896"))
    }

    func test_priceBarcodeWithDifferentPrefix_isInvalid() {
        // 日本の書籍に併記される価格表示用JANバーコード（例: 191等のCコード系）を誤って
        // ISBNとして扱わないことを確認する（要件定義書F-01/F-02）
        XCTAssertFalse(BarcodeScanService.isValidISBN13("1912000012345"))
    }

    func test_wrongLength_isInvalid() {
        XCTAssertFalse(BarcodeScanService.isValidISBN13("978404103140"))
        XCTAssertFalse(BarcodeScanService.isValidISBN13("97840410314001"))
    }
}
