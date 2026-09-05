import Foundation

protocol SeriesProgressCalculating {
    func calculateAll() throws -> [SeriesProgress]
    /// シリーズ名が判明しなかった（seriesKeyがnilの）本。所持・気になるの両方を含む
    /// （本棚統合画面で「本」セクションとして単独表示するため）。
    /// F-02の「気になるリストへ」はタイトル・シリーズ名未確定のまま登録されることが多いため、
    /// calculateAll()のシリーズカードだけでは表示漏れが起きる（気になる本棚に何も表示されない不具合の原因）。
    func standaloneBooks() throws -> [Book]
    /// キャッシュの再取得が必要な（未取得、または30日以上古い）シリーズキー一覧。
    /// SeriesVolumeCountRefreshServiceが非同期で既刊総数の再取得をトリガーする際に使用する。
    func seriesKeysNeedingRefresh() throws -> [String]
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
            // グループ内で最も多く使われている表記を代表シリーズ名として採用する。
            // Dictionary(grouping:)の要素順は不定であり、単純にfirst(where:)で選ぶと
            // ムック本・関連グッズ等、表記の異なる少数派の本がたまたま代表に選ばれてしまい、
            // NDL Searchへの既刊数検索（完全一致ベース）が空振りして「不明」になる不具合があった。
            let seriesName = Self.mostFrequentSeriesName(in: seriesBooks) ?? seriesKey

            let cache = try? metadataCache.cached(seriesKey: seriesKey)
            let (missingVolumes, completionRate, nextVolumeToBuy) = Self.progress(
                ownedVolumes: ownedVolumes,
                knownTotalVolumes: cache?.knownTotalVolumes
            )

            var nextVolumeISBN: String?
            if let next = nextVolumeToBuy {
                nextVolumeISBN = try? bookRepository.find(seriesKey: seriesKey, volumeNumber: next)?.isbn
            }

            let volumeEntries = seriesBooks
                .compactMap { book -> SeriesVolumeEntry? in
                    guard let volumeNumber = book.volumeNumber else { return nil }
                    return SeriesVolumeEntry(bookID: book.id, volumeNumber: volumeNumber, unifiedStatus: book.unifiedStatus)
                }
                .sorted { $0.volumeNumber < $1.volumeNumber }

            results.append(SeriesProgress(
                seriesKey: seriesKey,
                seriesName: seriesName,
                ownedVolumes: ownedVolumes,
                missingVolumes: missingVolumes,
                completionRate: completionRate,
                nextVolumeToBuy: nextVolumeToBuy,
                nextVolumeISBN: nextVolumeISBN,
                volumes: volumeEntries
            ))
        }

        return results.sorted { $0.seriesName < $1.seriesName }
    }

    func standaloneBooks() throws -> [Book] {
        try bookRepository.fetchAll()
            .filter { $0.seriesKey == nil }
            .sorted { $0.registeredAt > $1.registeredAt }
    }

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

    /// グループ内で最も出現頻度の高いseriesName文字列を返す（同数の場合は文字列としてより小さい方を
    /// 選び、実行のたびに結果が変わらないようにする）。
    private static func mostFrequentSeriesName(in books: [Book]) -> String? {
        let counts = Dictionary(grouping: books.compactMap(\.seriesName), by: { $0 })
            .mapValues(\.count)
        return counts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .first?.key
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
