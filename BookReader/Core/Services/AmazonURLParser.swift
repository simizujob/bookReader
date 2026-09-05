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

    /// "/dp/"の直前にあるタイトルスラグ（例: "プラチナデータ-幻冬舎文庫-東野圭吾-ebook"）から
    /// 先頭区間をタイトルの手掛かりとして取り出す。Amazonの商品ページURLは
    /// 「タイトル-レーベル-著者-（ebook等）」の順でハイフン区切りになっていることが多く、
    /// 先頭区間がタイトルに一致するケースが多い（Kindle版ASINは書籍のISBNと無関係なため、
    /// ISBN変換に失敗した場合の紙の本再検索用の手掛かりとして使う）。
    static func extractTitleHint(from url: URL) -> String? {
        let components = url.pathComponents
        // dpIndex >= 2が必要（index 0は常にルートの"/"であり、実際のスラグではないため）。
        guard let dpIndex = components.firstIndex(of: "dp"), dpIndex >= 2 else { return nil }
        let slug = components[dpIndex - 1]
        guard slug != "gp" else { return nil }
        guard let firstSegment = slug.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first,
              !firstSegment.isEmpty
        else { return nil }
        return String(firstSegment)
    }
}
