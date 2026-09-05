import Foundation

/// NDL Searchのdcndl:volume表記から実際の巻数を抽出する（詳細設計書9章参照）。
///
/// 実データを幅広く調査した結果、NDL内で巻数の表記は統一されておらず、以下のような
/// バリエーションが存在することを確認済み:
/// - 数字のみ（"5"）
/// - 「巻」+数字（"巻115"）、「第N巻」（"第1巻"、副題付き"第1巻 (寿限無)"も含む）
/// - "Vol.N" / "vol. N"（副題付き"Vol.1 (緑谷出久:オリジン)"も含む）
/// - 先頭が数字で副題が続くもの（"10 (樺太編4)"）
/// - ドイツ語表記の"Band N" / "N Band"
/// - 角括弧のみ（"[1]"）
/// - 上下巻・前後編等、同じ巻数を複数の実在する本が共有するもの（"1[上]"「1[下]」）
/// - 「部」単位で巻数が振り直されるもの（"第1部[1]"）
///
/// 一方で以下は巻数として採用すると誤った数字を自信ありげに返すことになるため、
/// 意図的に対象外とする:
/// - 週刊誌の号数（"No. 71"）— 単行本の巻数と対応しない
/// - 範囲・複数列挙（"v. 1-2-3"）— 1レコードに複数巻が混在
/// - 小数点表記（"0.5"）— 整数の巻数として扱えない特別巻
/// - 漢数字のみ（"巻一"）— 数字への変換が信頼できない
enum NDLVolumeParser {
    struct Result: Equatable {
        let number: Int
        /// 上/中/下、前編/中編/後編等、同じ巻数を持つ複数の本を画面上で区別するための表示マーカー。
        var marker: String?
        /// 「第N部[M]」のように、シリーズが部単位で分割されている場合の部番号。
        /// この場合numberは部内の巻数（M）を表す。
        var part: Int?
        /// 「巻N」「第N巻」のように「巻」という明示的な単位を伴う表記かどうか。
        /// 実データ調査の結果、同じタイトルで独自の巻数体系を持つ別編集（総集編・
        /// アニメコミックス等）が存在するシリーズ（ONE PIECE等）でも、本来の単行本は
        /// 例外なく「巻」付き表記である一方、別編集側は「N (副題)」のような「巻」なしの
        /// 裸数字表記しか使わないことを確認済み。NDLSearchServiceはこのフラグを使い、
        /// 「巻」付き表記が1件でも存在するタイトルでは「巻」なし表記を別編集とみなして除外する。
        var isExplicitCounter: Bool = false
    }

    /// 上下巻・前後編等、同じ巻数を複数の本が共有する際に区別するためのマーカー一覧。
    static let splitMarkers = ["上", "中", "下", "前編", "中編", "後編"]

    private static let daiBuPattern = try! NSRegularExpression(pattern: #"^第(\d+)部\[(\d+)\]$"#)
    private static let markerSuffixPattern = try! NSRegularExpression(
        pattern: #"^(\d+)[\(\[](上|中|下|前編|中編|後編)[\)\]]$"#
    )
    private static let plainDigitPattern = try! NSRegularExpression(pattern: #"^(\d+)$"#)
    private static let kanPrefixPattern = try! NSRegularExpression(pattern: #"^巻(\d+)$"#)
    private static let daiKanPattern = try! NSRegularExpression(pattern: #"^第(\d+)巻(?:\s*\(.+\))?$"#)
    private static let volDotPattern = try! NSRegularExpression(pattern: #"^[vV]ol\.?\s?(\d+)(?:\s*\(.+\))?$"#)
    private static let bracketOnlyPattern = try! NSRegularExpression(pattern: #"^\[(\d+)\]$"#)
    private static let genericSubtitlePattern = try! NSRegularExpression(pattern: #"^(\d+)\s*\(.+\)$"#)
    private static let bandPattern = try! NSRegularExpression(pattern: #"^(?:Band\s*(\d+)|(\d+)\s*Band)$"#)

    static func parse(_ raw: String) -> Result? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        if let match = daiBuPattern.firstMatch(in: text, range: range),
           let part = int(text, match, 1), let number = int(text, match, 2) {
            return Result(number: number, marker: nil, part: part)
        }

        if let match = markerSuffixPattern.firstMatch(in: text, range: range),
           let number = int(text, match, 1), let marker = substring(text, match, 2) {
            return Result(number: number, marker: marker, part: nil)
        }

        for pattern in [plainDigitPattern, kanPrefixPattern, daiKanPattern, volDotPattern, bracketOnlyPattern, genericSubtitlePattern] {
            if let match = pattern.firstMatch(in: text, range: range), let number = int(text, match, 1) {
                let isExplicitCounter = pattern === kanPrefixPattern || pattern === daiKanPattern
                return Result(number: number, marker: nil, part: nil, isExplicitCounter: isExplicitCounter)
            }
        }

        if let match = bandPattern.firstMatch(in: text, range: range),
           let number = int(text, match, 1) ?? int(text, match, 2) {
            return Result(number: number, marker: nil, part: nil)
        }

        return nil
    }

    private static func int(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text)
        else { return nil }
        return Int(text[range])
    }

    private static func substring(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> String? {
        guard group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[range])
    }
}
