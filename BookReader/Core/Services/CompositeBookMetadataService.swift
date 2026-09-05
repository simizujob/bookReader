import Foundation

/// 和書に強いopenBDを優先データソースとし、見つからない場合のみOpen Libraryを試す。
/// 既刊総数の推定（fetchSeriesVolumeCount）はopenBDが非対応のためOpen Libraryのみを使う。
final class CompositeBookMetadataService: BookMetadataFetching {
    private let primary: BookMetadataFetching
    private let fallback: BookMetadataFetching

    init(
        primary: BookMetadataFetching = OpenBDService(),
        fallback: BookMetadataFetching = OpenLibraryService()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func fetchMetadata(isbn: String) async throws -> BookMetadata {
        if let result = try? await primary.fetchMetadata(isbn: isbn) {
            return result
        }
        return try await fallback.fetchMetadata(isbn: isbn)
    }

    func fetchSeriesVolumeCount(seriesName: String) async throws -> Int? {
        try await fallback.fetchSeriesVolumeCount(seriesName: seriesName)
    }
}
