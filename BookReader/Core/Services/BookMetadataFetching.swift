import Foundation

struct BookMetadata: Equatable {
    let title: String
    let coverImageURL: String?
}

/// ISBNから書籍のタイトル・表紙画像を取得するサービスの共通プロトコル。
/// Open Library・openBDなど複数のデータソースを同一インターフェースで扱う。
protocol BookMetadataFetching {
    func fetchMetadata(isbn: String) async throws -> BookMetadata
    /// 既刊総数の暫定推定値（詳細設計書4.7参照、要件定義書14章のリスクを踏まえた暫定ロジック）。
    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int?
}
