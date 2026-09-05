import Foundation

/// 「持っていません」判定からの気になるリスト登録処理。買う前チェック（カメラ）・
/// 共有シート（Amazon商品ページから）のどちらの入口からも同じ重複登録防止ルールを
/// 適用するために切り出す。
enum WishlistRegistrar {
    struct Entry {
        let isbn: String
        let title: String
        let seriesName: String?
        let volumeNumber: Int?
        let coverImageURL: String?
        let metadataFetched: Bool
    }

    /// 既刊数が判明したシリーズは未登録の巻をISBN未確定のプレースホルダーとして
    /// 自動登録している（SeriesVolumeCountRefreshService.backfillMissingVolumes）。
    /// 同じ巻を実際にチェックした場合、新規登録せずそのプレースホルダーを実データで更新する
    /// （重複登録の防止）。
    static func register(_ entry: Entry, bookRepository: BookRepository) {
        if let seriesName = entry.seriesName,
           let volumeNumber = entry.volumeNumber,
           let placeholder = try? bookRepository.find(
               seriesKey: SeriesKeyNormalizer.normalize(seriesName),
               volumeNumber: volumeNumber
           ),
           placeholder.isbn == nil {
            _ = try? bookRepository.update(
                id: placeholder.id,
                changes: BookChanges(
                    title: entry.title,
                    seriesName: seriesName,
                    volumeNumber: volumeNumber,
                    isbn: entry.isbn,
                    coverImageURL: entry.coverImageURL,
                    status: .wishlist,
                    readStatus: placeholder.readStatus
                )
            )
        } else {
            _ = try? bookRepository.insert(BookDraft(
                isbn: entry.isbn,
                title: entry.title,
                seriesName: entry.seriesName,
                volumeNumber: entry.volumeNumber,
                coverImageURL: entry.coverImageURL,
                status: .wishlist,
                readStatus: .unread,
                metadataFetched: entry.metadataFetched
            ))
        }
    }
}
