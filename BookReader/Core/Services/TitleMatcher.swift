import Foundation

/// あいまいタイトル一致。F-02版違い警告・F-03確認UIの両方で共通利用する（詳細設計書4.6）。
enum TitleMatcher {
    static func normalize(_ raw: String) -> String {
        var s = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: #"[\s　]+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"[「」『』（）()・:：〜~\-－]"#,
            with: "",
            options: .regularExpression
        )
        return s.lowercased()
    }

    /// 0.0〜1.0の類似度（1.0が完全一致）。正規化後の文字列に対しLevenshtein距離を用いる。
    static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a)
        let nb = normalize(b)
        if na.isEmpty || nb.isEmpty { return 0 }
        if na == nb { return 1 }
        let distance = levenshteinDistance(Array(na), Array(nb))
        let maxLen = max(na.count, nb.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[b.count]
    }
}
