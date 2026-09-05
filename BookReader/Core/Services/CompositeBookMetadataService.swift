import Foundation

/// 複数の書誌データソースを優先順位付きで束ねる。
/// 1. NDL Search — 国内出版物の網羅性が最も高く、巻数を構造化フィールドで提供（表紙画像は無し）
/// 2. openBD — 日本の書籍に強く、表紙画像も提供されることがある
/// 3. Open Library — 主に洋書向け。前2つで見つからない場合の最終フォールバック
///
/// タイトル・シリーズ情報は最初に成功したソースを採用し、表紙画像だけは
/// 見つかるまで後続のソースでも探し続ける（NDLはタイトルは強いが表紙が無いため）。
final class CompositeBookMetadataService: BookMetadataFetching {
    private let sources: [BookMetadataFetching]

    init(sources: [BookMetadataFetching] = [NDLSearchService(), OpenBDService(), OpenLibraryService()]) {
        self.sources = sources
    }

    func fetchMetadata(isbn: String) async throws -> BookMetadata {
        var best: BookMetadata?

        for source in sources {
            guard let result = try? await source.fetchMetadata(isbn: isbn) else { continue }

            if let current = best {
                if current.coverImageURL == nil, let cover = result.coverImageURL {
                    best = BookMetadata(
                        title: current.title,
                        coverImageURL: cover,
                        seriesName: current.seriesName,
                        volumeNumber: current.volumeNumber
                    )
                }
            } else {
                best = result
            }

            if best?.coverImageURL != nil { break }
        }

        guard let best else { throw BookMetadataError.notFound }
        return best
    }

    func fetchSeriesVolumeCount(seriesName: String) async throws -> SeriesVolumeCountResult? {
        for source in sources {
            if let result = try? await source.fetchSeriesVolumeCount(seriesName: seriesName) {
                return result
            }
        }
        return nil
    }
}
