import Foundation

/// シリーズ名の表記ゆれを吸収し、グルーピング・キャッシュ照合用の正規化キーを生成する。
/// 詳細設計書4.3参照。
enum SeriesKeyNormalizer {
    private static let trailingVolumePattern: NSRegularExpression = {
        // 例: "(1)" "1" "第1巻" "vol.1" を末尾から除去する
        try! NSRegularExpression(pattern: #"(\(\d+\)|第\d+巻|巻?\d+|[vV]ol\.?\s?\d+)$"#)
    }()

    static func normalize(_ raw: String) -> String {
        var s = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"[\s　]+"#, with: "", options: .regularExpression)

        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        if let match = trailingVolumePattern.firstMatch(in: s, range: range),
           let matchRange = Range(match.range, in: s) {
            s.removeSubrange(matchRange)
        }

        return s.lowercased()
    }
}
