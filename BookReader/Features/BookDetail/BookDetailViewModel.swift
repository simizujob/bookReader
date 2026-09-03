import Foundation

/// 本の詳細/編集（F-08）。詳細設計書5.5参照。
@MainActor
final class BookDetailViewModel: ObservableObject {
    let bookID: UUID
    @Published var editableTitle: String
    @Published var editableSeriesName: String
    @Published var editableVolumeNumber: Int?
    @Published var editableStatus: OwnershipStatus
    @Published var editableReadStatus: ReadStatus
    @Published var showDeleteConfirm = false
    @Published var errorMessage: String?
    @Published private(set) var didDelete = false

    private let bookRepository: BookRepository

    init(book: Book, bookRepository: BookRepository) {
        self.bookID = book.id
        self.editableTitle = book.title
        self.editableSeriesName = book.seriesName ?? ""
        self.editableVolumeNumber = book.volumeNumber
        self.editableStatus = book.status
        self.editableReadStatus = book.readStatus
        self.bookRepository = bookRepository
    }

    @discardableResult
    func save() -> Bool {
        do {
            try bookRepository.update(
                id: bookID,
                changes: BookChanges(
                    title: editableTitle,
                    seriesName: editableSeriesName.isEmpty ? nil : editableSeriesName,
                    volumeNumber: editableVolumeNumber,
                    status: editableStatus,
                    readStatus: editableReadStatus
                )
            )
            return true
        } catch {
            errorMessage = "保存に失敗しました。もう一度お試しください"
            return false
        }
    }

    func delete() {
        do {
            try bookRepository.delete(id: bookID)
            didDelete = true
        } catch {
            errorMessage = "保存に失敗しました。もう一度お試しください"
        }
    }
}
