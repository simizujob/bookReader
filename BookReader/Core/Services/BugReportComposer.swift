import Foundation

/// 不具合報告メールの宛先・件名・本文を組み立てる。
/// MFMailComposeViewController（UIKit）に依存させず、本文組み立てだけを単体テストできるようにする。
enum BugReportComposer {
    static let recipientEmail = "tiktok.play.sub01@gmail.com"

    static func report(for book: Book) -> (subject: String, body: String) {
        let subject = "【積読レーダー】不具合報告: \(book.title)"

        var lines = ["以下の本について不具合を報告します。", "", "---"]
        lines.append("タイトル: \(book.title)")
        if let seriesName = book.seriesName {
            lines.append("シリーズ名: \(seriesName)")
        }
        if let volumeNumber = book.volumeNumber {
            lines.append("巻数: \(volumeNumber)")
        }
        if let isbn = book.isbn {
            lines.append("ISBN: \(isbn)")
        }
        lines.append("---")
        lines.append("")
        lines.append("不具合の内容:")
        lines.append("（ここに詳細をご記入ください）")

        return (subject, lines.joined(separator: "\n"))
    }

    static func report(for series: SeriesProgress) -> (subject: String, body: String) {
        let subject = "【積読レーダー】不具合報告: \(series.seriesName)（シリーズ）"

        var lines = ["以下のシリーズについて不具合を報告します。", "", "---"]
        lines.append("シリーズ名: \(series.seriesName)")
        if let rate = series.completionRate {
            lines.append("完結率: \(Int(rate * 100))%")
        } else {
            lines.append("既刊数: 不明")
        }
        lines.append("所持巻数: \(series.ownedVolumes.count)巻")
        let ownedList = series.ownedVolumes.sorted().map(String.init).joined(separator: ", ")
        lines.append("所持している巻: \(ownedList)")
        if let missingVolumes = series.missingVolumes, !missingVolumes.isEmpty {
            let missingList = missingVolumes.sorted().map(String.init).joined(separator: ", ")
            lines.append("未所持の巻: \(missingList)")
        }
        lines.append("---")
        lines.append("")
        lines.append("不具合の内容:")
        lines.append("（ここに詳細をご記入ください）")

        return (subject, lines.joined(separator: "\n"))
    }
}
