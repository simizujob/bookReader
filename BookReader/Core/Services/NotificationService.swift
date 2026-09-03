import Foundation
import UserNotifications

protocol ReminderScheduling {
    func scheduleReminder(for book: Book)
    func cancelReminder(bookID: UUID)
}

/// 積読リマインド通知（F-04）。詳細設計書4.10参照。
/// 呼び出し元はBookRepositoryの書き込み後処理のみとし、ViewModelから直接呼び出さない。
struct NotificationService: ReminderScheduling {
    static let reminderThresholdDays = 30

    func scheduleReminder(for book: Book) {
        guard let triggerDate = Calendar.current.date(
            byAdding: .day,
            value: Self.reminderThresholdDays,
            to: book.registeredAt
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = "積読、そろそろ読みませんか？"
        content.body = "「\(book.title)」を登録してから\(Self.reminderThresholdDays)日が経ちました。"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: book.id.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(bookID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [bookID.uuidString])
    }
}
