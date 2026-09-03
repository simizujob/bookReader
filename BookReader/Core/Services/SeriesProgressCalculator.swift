import Foundation

protocol SeriesProgressCalculating {
    func calculateAll() throws -> [SeriesProgress]
    /// シリーズ名が判明しなかった（seriesKeyがnilの）気になるリスト登録本。
    /// F-02の「気になるリストへ」はタイトル・シリーズ名未確定のまま登録されることが多いため、
    /// calculateAll()のシリーズカードだけでは表示漏れが起きる（気になる本棚に何も表示されない不具合の原因）。
    func standaloneWishlistBooks() throws -> [Book]
}

/// シリーズ完結率の算出（F-05）。詳細設計書4.2参照。
/// 既刊総数が不明な場合は完結率を断定表示せず、所持巻の最大値+1を暫定候補とする
/// フォールバック仕様（要件定義書F-05）を実装する。
final class SeriesProgressCalculator: SeriesProgressCalculating {
    /// このキャッシュ鮮度を超えたら再取得が必要と判断する（呼び出し元がbackfillをトリガーする際に使用）
    static let cacheStalenessDays = 30

    private let bookRepository: BookRepository
    private let metadataCache: SeriesMetadataCaching

    init(bookRepository: BookRepository, metadataCache: SeriesMetadataCaching) {
        self.bookRepository = bookRepository
        self.metadataCache = metadataCache
    }

    func calculateAll() throws -> [SeriesProgress] {
        let books = try bookRepository.fetchAll()
            .filter { $0.status == .owned || $0.status == .wishlist }
            .filter { $0.seriesKey != nil }

        let grouped = Dictionary(grouping: books) { $0.seriesKey! }

        var results: [SeriesProgress] = []
        for (seriesKey, seriesBooks) in grouped {
            let ownedVolumes = seriesBooks
                .filter { $0.status == .owned }
                .compactMap { $0.volumeNumber }
                .sorted()
            let seriesName = seriesBooks.first(where: { $0.seriesName != nil })?.seriesName ?? seriesKey

            let cache = try? metadataCache.cached(seriesKey: seriesKey)
            let (missingVolumes, completionRate, nextVolumeToBuy) = Self.progress(
                ownedVolumes: ownedVolumes,
                knownTotalVolumes: cache?.knownTotalVolumes
            )

            var nextVolumeISBN: String?
            if let next = nextVolumeToBuy {
                nextVolumeISBN = try? bookRepository.find(seriesKey: seriesKey, volumeNumber: next)?.isbn
            }

            results.append(SeriesProgress(
                seriesKey: seriesKey,
                seriesName: seriesName,
                ownedVolumes: ownedVolumes,
                missingVolumes: missingVolumes,
                completionRate: completionRate,
                nextVolumeToBuy: nextVolumeToBuy,
                nextVolumeISBN: nextVolumeISBN
            ))
        }

        return results.sorted { $0.seriesName < $1.seriesName }
    }

    func standaloneWishlistBooks() throws -> [Book] {
        try bookRepository.fetchAll()
            .filter { $0.status == .wishlist && $0.seriesKey == nil }
            .sorted { $0.registeredAt > $1.registeredAt }
    }

    /// キャッシュの再取得が必要な（未取得、または30日以上古い）シリーズキー一覧。
    /// MetadataBackfillServiceが非同期でOpen Libraryへの再取得をトリガーする際に使用する。
    func seriesKeysNeedingRefresh() throws -> [String] {
        let seriesKeys = Set(try bookRepository.fetchAll().compactMap { $0.seriesKey })
        return try seriesKeys.filter { key in
            guard let cache = try metadataCache.cached(seriesKey: key) else { return true }
            let staleDate = Calendar.current.date(
                byAdding: .day, value: -Self.cacheStalenessDays, to: Date()
            ) ?? .distantPast
            return cache.lastFetchedAt < staleDate
        }
    }

    private static func progress(
        ownedVolumes: [Int],
        knownTotalVolumes: Int?
    ) -> (missingVolumes: [Int]?, completionRate: Double?, nextVolumeToBuy: Int?) {
        guard let total = knownTotalVolumes, total > 0 else {
            let next = (ownedVolumes.max() ?? 0) + 1
            return (nil, nil, next)
        }
        let owned = Set(ownedVolumes)
        let missing = (1...total).filter { !owned.contains($0) }
        let rate = Double(ownedVolumes.count) / Double(total)
        return (missing, rate, missing.first)
    }
}
