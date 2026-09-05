import XCTest
@testable import BookReader

final class ISBNConverterTests: XCTestCase {
    func test_validISBN10ASIN_convertsToISBN13() {
        // 0-306-40615-2 はISBN-10チェックディジット解説でよく使われる既知の正しい例。
        // ISBN-13は978プレフィックス+先頭9桁+新チェックディジットで9780306406157になる。
        XCTAssertEqual(ISBNConverter.isbn13(fromASIN: "0306406152"), "9780306406157")
    }

    func test_validISBN10ASINEndingInX_convertsToISBN13() {
        // チェックディジットが"X"（10を表す）になる既知の正しい例。
        XCTAssertEqual(ISBNConverter.isbn13(fromASIN: "080442957X"), "9780804429573")
    }

    func test_invalidChecksum_returnsNil() {
        // 桁数・文字種はISBN-10らしいが、チェックディジットが合わない（＝ISBN由来でないASIN）。
        XCTAssertNil(ISBNConverter.isbn13(fromASIN: "0306406153"))
    }

    func test_kindleStyleASIN_returnsNil() {
        // Kindle版などISBN由来でないASINは英字を含み、そもそもISBN-10として解釈できない。
        XCTAssertNil(ISBNConverter.isbn13(fromASIN: "B00ZY7L1QG"))
    }

    func test_wrongLength_returnsNil() {
        XCTAssertNil(ISBNConverter.isbn13(fromASIN: "12345"))
    }
}
