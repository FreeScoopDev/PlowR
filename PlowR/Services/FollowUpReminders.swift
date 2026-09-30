import Foundation
import SwiftData
import UserNotifications

/// Reminders to follow up on quotes with no reply (Pipeline.followUpDates):
/// one notification per client, at 9 AM on the day the quote has waited
/// long enough. Replaced as a set each time from what's on file, when the
/// app starts, comes back, and goes to the background, so what's due when
/// the business isn't in the app is right when they left it.
enum FollowUpReminders {
    static let prefix = "follow_up_"

    /// The notifications for `dates`.
    static func requests(_ dates: [(client: Client, date: Date)], calendar: Calendar = .current)
        -> [UNNotificationRequest] {
        dates.map { client, date in
            let content = UNMutableNotificationContent()
            content.title = "Follow Up with \(client.name)"
            content.body = "No reply to your proposal in \(Pipeline.followUpDays) days."
            content.sound = .default
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return UNNotificationRequest(identifier: prefix + client.id.uuidString, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        }
    }

    /// Replaces the pending reminders with those due now for `operatorID`'s
    /// clients (none when signed out).
    static func refresh(operatorID: String, in context: ModelContext, now: Date = .now) {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        let entries = operatorID.isEmpty ? []
            : Pipeline.entries(clients, operatorID: operatorID, facts: Pipeline.Facts(in: context), now: now)
        let wanted = requests(Pipeline.followUpDates(entries, now: now))
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            wanted.forEach { center.add($0) }
        }
    }
}
