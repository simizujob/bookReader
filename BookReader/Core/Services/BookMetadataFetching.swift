import Foundation

struct BookMetadata: Equatable {
    let title: String
    let coverImageURL: String?
    /// データソースが構造化フィールドとして提供する場合のみ設定される（例: NDL Searchのdcndl:volume、
    /// openBDのsummary.series/volume）。nilの場合は呼び出し側がTitleParserでtitleから推定する
    /// （resolvedSeriesInfo参照）。
    let seriesName: String?
    let volumeNumber: Int?

    init(title: String, coverImageURL: String? = nil, seriesName: String? = nil, volumeNumber: Int? = nil) {
        self.title = title
        self.coverImageURL = coverImageURL
        self.seriesName = seriesName
        self.volumeNumber = volumeNumber
    }

    /// データソースが構造化されたシリーズ名・巻数を提供していればそれを優先し、
    /// なければTitleParserでtitleから推定する。両方のケースを一箇所に集約する。
    var resolvedSeriesInfo: (seriesName: String?, volumeNumber: Int?) {
        if let seriesName, let volumeNumber {
            return (seriesName, volumeNumber)
        }
        let parsed = TitleParser.parse(title)
        return (parsed.seriesName, parsed.volumeNumber)
    }
}

enum BookMetadataError: Error, Equatable {
    case notFound
}

/// 既刊総数のベストエフォート推定結果。
struct SeriesVolumeCountResult: Equatable {
    /// 1巻から連続して確認できた最大巻。
    let total: Int
    /// データソースが巻ごとのISBNを構造化フィールドとして提供している場合のみ埋まる
    /// （現状NDL Searchのみ対応）。全巻自動登録の際、キーワード検索ではなくISBN検索の
    /// Amazon購入リンクを使えるようにするために保持する。
    let isbnsByVolume: [Int: String]
}

/// ISBNから書籍のタイトル・表紙画像を取得するサービスの共通プロトコル。
/// NDL Search・openBD・Open Libraryなど複数のデータソースを同一インターフェースで扱う。
protocol BookMetadataFetching {
    func fetchMetadata(isbn: String) async throws -> BookMetadata
    /// 既刊総数の暫定推定値（詳細設計書4.7参照、要件定義書14章のリスクを踏まえた暫定ロジック）。
    /// ベストエフォート方針: 著者名によるクエリ絞り込みは検証の結果、生データの表記ゆれ
    /// （読点・生年付記・異体字など）が原因で信頼できないと判明したため採用しない。
    /// 代わりに「1巻から最大巻まで欠番なく検出できた場合のみ」採用し、少しでも歯抜けがあれば
    /// nilを返す（誤った既刊数を自信ありげに表示するより「不明」の方が安全という判断）。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> SeriesVolumeCountResult?
}
