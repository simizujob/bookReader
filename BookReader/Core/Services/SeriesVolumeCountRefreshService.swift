import Foundation

protocol SeriesVolumeCountRefreshing {
    func refreshStaleSeries() async
    /// キャッシュの鮮度に関わらず全シリーズを再取得する。本棚画面のpull-to-refresh用。
    /// 既刊数取得ロジック自体を変更した直後など、「不明」等の古い結果がキャッシュされたまま
    /// 最大30日再取得されない、という状況をユーザー自身がすぐ解消できるようにするために必要。
    func refreshAllSeries() async
    /// 既刊数が自動では判明しないシリーズについて、ユーザーが手動で入力した数値をその場しのぎの
    /// 値として採用する。既刊数が判明した場合と全く同じ経路（キャッシュ保存＋未登録の巻の
    /// 自動登録）を通すため、以後の自動チェック（30日後、または依然不明の場合は毎回）で
    /// 上書きされうる暫定値という位置づけになる。
    func setManualVolumeCount(seriesKey: String, seriesName: String, total: Int) async
}

/// 既刊総数キャッシュの再取得（F-05）。詳細設計書4.2「seriesKeysNeedingRefresh」を実際に
/// 呼び出して結果をキャッシュへ書き込む配線部分（従来ここが未接続で、既刊数が常に「不明」の
/// ままになっていた）。MetadataBackfillServiceと同様、アプリのscenePhaseが.activeになった
/// タイミングで呼び出す想定。
struct SeriesVolumeCountRefreshService: SeriesVolumeCountRefreshing {
    /// 外部データソース（BookMetadataFetching実装）が返す既刊総数の上限。実在する国内漫画で
    /// 最も長期連載のシリーズでも300巻に満たないため、これを超える値は自由文字列検索の
    /// ヒット件数を誤って返す等、既刊総数として意味を成さないデータと判断して破棄する。
    /// 全巻自動登録（backfillMissingVolumes）が暴走して大量の偽レコードを作らないための
    /// 最終防衛ライン（境界での検証）。
    static let maxPlausibleVolumeCount = 500

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
        await refresh(seriesKeys: staleKeys)
    }

    func refreshAllSeries() async {
        guard let allSeries = try? calculator.calculateAll(), !allSeries.isEmpty else { return }
        await refresh(seriesKeys: allSeries.map(\.seriesKey))
    }

    func setManualVolumeCount(seriesKey: String, seriesName: String, total: Int) async {
        guard total > 0, total <= Self.maxPlausibleVolumeCount else { return }
        try? metadataCache.upsert(seriesKey: seriesKey, totalVolumes: total)
        guard let allSeries = try? calculator.calculateAll(),
              let series = allSeries.first(where: { $0.seriesKey == seriesKey }) else { return }
        backfillMissingVolumes(
            seriesName: seriesName,
            total: total,
            existingVolumeNumbers: Set(series.volumes.map(\.volumeNumber))
        )
    }

    private func refresh(seriesKeys: [String]) async {
        // SeriesProgressCalculator.calculateAll()がグループ内の多数決で選んだ代表表記をそのまま使う。
        // 以前はbookRepository.fetchAll()の配列内でたまたま先頭に来た本の表記をそのまま検索クエリに
        // 使っており、ムック本など少数派の表記の本が先頭になるとNDL検索が空振りして既刊数が
        // 「不明」になる不具合があった（表示用のシリーズ名選択だけを多数決化し、検索クエリ用の
        // この箇所を直し忘れていたのが原因）。
        guard let allSeries = try? calculator.calculateAll() else { return }
        let seriesByKey = Dictionary(uniqueKeysWithValues: allSeries.map { ($0.seriesKey, $0) })

        for seriesKey in seriesKeys {
            guard let series = seriesByKey[seriesKey] else { continue }
            let seriesName = series.seriesName
            let rawCount = try? await metadataService.fetchSeriesVolumeCount(seriesName: seriesName)
            let count = rawCount.flatMap { $0 <= Self.maxPlausibleVolumeCount ? $0 : nil }
            try? metadataCache.upsert(seriesKey: seriesKey, totalVolumes: count)
            if let total = count, total > 0 {
                backfillMissingVolumes(
                    seriesName: seriesName,
                    total: total,
                    existingVolumeNumbers: Set(series.volumes.map(\.volumeNumber))
                )
            }
            try? await Task.sleep(nanoseconds: interRequestDelayNanoseconds)
        }
    }

    /// 既刊総数が判明したシリーズについて、本棚に未登録の巻を「気になる本棚」（未購入）として
    /// まとめて自動登録する。本棚統合画面でシリーズの全巻を一覧表示し、どの巻が未読／未購入かを
    /// 一目で分かるようにするためのユーザー要望対応。実物をスキャンせずAmazon等で購入する
    /// ケースもあるため、ISBNなしのまま登録し購入導線はキーワード検索の購入リンクで代替する。
    private func backfillMissingVolumes(seriesName: String, total: Int, existingVolumeNumbers: Set<Int>) {
        let missing = (1...total).filter { !existingVolumeNumbers.contains($0) }
        guard !missing.isEmpty else { return }

        let drafts = missing.map { volume in
            BookDraft(
                isbn: nil,
                title: "\(seriesName) \(volume)",
                seriesName: seriesName,
                volumeNumber: volume,
                coverImageURL: nil,
                status: .wishlist,
                readStatus: .unread,
                metadataFetched: true
            )
        }
        _ = try? bookRepository.insertBatch(drafts)
    }
}
