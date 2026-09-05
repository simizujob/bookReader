import Foundation

/// 書籍のASIN（AmazonがISBN-10をそのまま商品コードとして使っていることが多い）を
/// ISBN-13へ変換する。judge(isbn:)や各種メタデータAPIはISBN-13を前提としているため。
enum ISBNConverter {
    /// ASINがISBN-10のチェックディジットとして妥当な場合のみISBN-13へ変換する。
    /// Kindle版等、ISBN由来でないASIN（チェックディジットが合わないもの）はnilを返す。
    static func isbn13(fromASIN asin: String) -> String? {
        let candidate = asin.uppercased()
        guard isValidISBN10(candidate) else { return nil }
        let first9 = String(candidate.prefix(9))
        let base = "978" + first9
        return base + String(isbn13CheckDigit(forFirst12: base))
    }

    private static func isValidISBN10(_ isbn10: String) -> Bool {
        let chars = Array(isbn10)
        guard chars.count == 10 else { return false }
        var sum = 0
        for (index, char) in chars.enumerated() {
            let value: Int
            if index == 9, char == "X" {
                value = 10
            } else if char.isNumber, let digit = char.wholeNumberValue {
                value = digit
            } else {
                return false
            }
            sum += value * (10 - index)
        }
        return sum % 11 == 0
    }

    private static func isbn13CheckDigit(forFirst12 first12: String) -> Int {
        let digits = first12.compactMap(\.wholeNumberValue)
        let sum = digits.enumerated().reduce(0) { partial, pair in
            let (index, digit) = pair
            return partial + digit * (index % 2 == 0 ? 1 : 3)
        }
        return (10 - (sum % 10)) % 10
    }
}
