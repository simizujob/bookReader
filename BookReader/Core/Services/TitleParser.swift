import Foundation

/// 生のタイトル文字列（OCR抽出結果、またはOpen Libraryのtitleフィールド）から
/// シリーズ名・巻数を抽出する。詳細設計書4.3a参照。
/// Open Libraryはシリーズ名・巻数を構造化フィールドとして提供しないため、
/// タイトル文字列を解析して分解する必要がある。
enum TitleParser {
    struct Result: Equatable {
        let title: String
        let seriesName: String?
        let volumeNumber: Int?
    }

    private static let pattern: NSRegularExpression = {
        // グループ1: シリーズ名本体 / グループ2-5: 各表記パターンでの巻数
        try! NSRegularExpression(
            pattern: #"^(.+?)[\s　]*(?:\((\d+)\)|第(\d+)巻|[vV]ol\.?\s?(\d+)|[\s　](\d+))$"#
        )
    }()

    static func parse(_ rawTitle: String) -> Result {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)

        guard let match = pattern.firstMatch(in: trimmed, range: range) else {
            return Result(title: trimmed, seriesName: nil, volumeNumber: nil)
        }

        let seriesName = substring(in: trimmed, at: 1, of: match)
        let volumeNumber = (2...5).lazy
            .compactMap { substring(in: trimmed, at: $0, of: match) }
            .compactMap { Int($0) }
            .first

        guard let seriesName, let volumeNumber else {
            return Result(title: trimmed, seriesName: nil, volumeNumber: nil)
        }

        return Result(title: trimmed, seriesName: seriesName, volumeNumber: volumeNumber)
    }

    private static func substring(in source: String, at index: Int, of match: NSTextCheckingResult) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: source) else { return nil }
        return String(source[range])
    }
}
