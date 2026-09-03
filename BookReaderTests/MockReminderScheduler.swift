import Foundation
@testable import BookReader

final class MockReminderScheduler: ReminderScheduling {
    private(set) var scheduledBookIDs: [UUID] = []
    private(set) var cancelledBookIDs: [UUID] = []

    func scheduleReminder(for book: Book) {
        scheduledBookIDs.append(book.id)
    }

    func cancelReminder(bookID: UUID) {
        cancelledBookIDs.append(bookID)
    }
}
