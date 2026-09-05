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

/// ISBNから書籍のタイトル・表紙画像を取得するサービスの共通プロトコル。
/// NDL Search・openBD・Open Libraryなど複数のデータソースを同一インターフェースで扱う。
protocol BookMetadataFetching {
    func fetchMetadata(isbn: String) async throws -> BookMetadata
    /// 既刊総数の暫定推定値（詳細設計書4.7参照、要件定義書14章のリスクを踏まえた暫定ロジック）。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int?
}
