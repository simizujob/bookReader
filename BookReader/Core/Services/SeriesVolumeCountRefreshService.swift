import Foundation

protocol SeriesVolumeCountRefreshing {
    func refreshStaleSeries() async
}

/// 既刊総数キャッシュの再取得（F-05）。詳細設計書4.2「seriesKeysNeedingRefresh」を実際に
/// 呼び出して結果をキャッシュへ書き込む配線部分（従来ここが未接続で、既刊数が常に「不明」の
/// ままになっていた）。MetadataBackfillServiceと同様、アプリのscenePhaseが.activeになった
/// タイミングで呼び出す想定。
struct SeriesVolumeCountRefreshService: SeriesVolumeCountRefreshing {
    private let bookRepository: BookRepository
    private let calculator: SeriesProgressCalculating
    private let metadataCache: SeriesMetadataCaching
    private let metadataService: BookMetadataFetching
    private let interRequestDelayNanoseconds: UInt64

    init(
        bookRepository: BookRepository,
        calculator: SeriesProgressCalculating,
        metadataCache: SeriesMetadataCaching,
        metadataService: BookMetadataFetching,
        interRequestDelayNanoseconds: UInt64 = 200_000_000
    ) {
        self.bookRepository = bookRepository
        self.calculator = calculator
        self.metadataCache = metadataCache
        self.metadataService = metadataService
        self.interRequestDelayNanoseconds = interRequestDelayNanoseconds
    }

    func refreshStaleSeries() async {
        guard let staleKeys = try? calculator.seriesKeysNeedingRefresh(), !staleKeys.isEmpty else { return }
        guard let allBooks = try? bookRepository.fetchAll() else { return }

        for seriesKey in staleKeys {
            // seriesKeyは正規化済みの内部キーのため、検索には元の表示用シリーズ名が必要。
            guard let seriesName = allBooks.first(where: { $0.seriesKey == seriesKey })?.seriesName else { continue }
            let count = try? await metadataService.fetchSeriesVolumeCount(seriesName: seriesName)
            try? metadataCache.upsert(seriesKey: seriesKey, totalVolumes: count ?? nil)
            try? await Task.sleep(nanoseconds: interRequestDelayNanoseconds)
        }
    }
}
