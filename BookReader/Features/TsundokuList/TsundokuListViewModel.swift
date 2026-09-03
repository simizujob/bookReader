import Foundation

/// 積読リスト（F-04）。詳細設計書5.3参照。
@MainActor
final class TsundokuListViewModel: ObservableObject {
    @Published var segment: ReadStatus = .unread
    @Published private(set) var books: [Book] = []
    @Published var errorMessage: String?

    static let overdueThresholdDays = NotificationService.reminderThresholdDays

    private let bookRepository: BookRepository

    init(bookRepository: BookRepository) {
        self.bookRepository = bookRepository
    }

    func onAppear() {
        reload()
    }

    func reload() {
        do {
            books = try bookRepository.fetchBySegment(segment)
                .sorted { $0.registeredAt < $1.registeredAt }
        } catch {
            errorMessage = "保存に失敗しました。もう一度お試しください"
        }
    }

    func markAsFinished(_ book: Book) {
        do {
            try bookRepository.update(
                id: book.id,
                changes: BookChanges(
                    title: book.title,
                    seriesName: book.seriesName,
                    volumeNumber: book.volumeNumber,
                    status: .owned,
                    readStatus: .finished
                )
            )
            reload()
        } catch {
            errorMessage = "保存に失敗しました。もう一度お試しください"
        }
    }

    func elapsedDays(for book: Book) -> Int {
        book.elapsedDays()
    }

    func isOverdue(_ book: Book) -> Bool {
        elapsedDays(for: book) >= Self.overdueThresholdDays
    }
}
