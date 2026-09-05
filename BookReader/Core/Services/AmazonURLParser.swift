import Foundation

/// Amazon商品ページのURLからASIN（10桁の商品コード）を抽出する。
/// 共有シート機能（買う前チェックの入り口をAmazon商品ページからも開けるようにする）で使用する。
enum AmazonURLParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"/(?:dp|gp/product)/([A-Za-z0-9]{10})(?:[/?]|$)"#
    )

    /// "/dp/XXXXXXXXXX" "/gp/product/XXXXXXXXXX" 形式のパスからASINを取り出す。
    /// 検索結果ページ等、該当しないURLはnilを返す。
    static func extractASIN(from url: URL) -> String? {
        let path = url.path
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = pattern.firstMatch(in: path, range: range),
              let asinRange = Range(match.range(at: 1), in: path)
        else { return nil }
        return String(path[asinRange])
    }
}
