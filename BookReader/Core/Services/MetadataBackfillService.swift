import Foundation

protocol MetadataBackfilling {
    func backfillPendingMetadata() async
}

/// オフラインで登録された本のタイトル・シリーズ情報を、オンライン復帰後に補完する（詳細設計書4.8）。
/// アプリのscenePhaseが.activeになったタイミングで呼び出す想定。
struct MetadataBackfillService: MetadataBackfilling {
    private let bookRepository: BookRepository
    private let metadataService: BookMetadataFetching
    private let interRequestDelayNanoseconds: UInt64

    init(
        bookRepository: BookRepository,
        metadataService: BookMetadataFetching,
        interRequestDelayNanoseconds: UInt64 = 200_000_000
    ) {
        self.bookRepository = bookRepository
        self.metadataService = metadataService
        self.interRequestDelayNanoseconds = interRequestDelayNanoseconds
    }

    func backfillPendingMetadata() async {
        guard let pending = try? bookRepository.fetchPendingMetadata(), !pending.isEmpty else { return }

        for book in pending {
            guard let isbn = book.isbn else { continue }
            if let meta = try? await metadataService.fetchMetadata(isbn: isbn) {
                try? bookRepository.applyMetadata(id: book.id, title: meta.title, coverImageURL: meta.coverImageURL)
            }
            try? await Task.sleep(nanoseconds: interRequestDelayNanoseconds)
        }
    }
}
