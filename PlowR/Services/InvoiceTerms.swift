import Foundation

/// When an invoice is due, and when it's late, in calendar days (Joe,
/// 2026-10-18).
///
/// A due date used to be "now + 720 hours", time of day included, and an
/// invoice was late the instant that passed. One sent at 2 pm on Oct 17
/// said "Due Nov 16" but was overdue by 1 pm on Nov 16 (the clocks change in
/// between), counted as late, joined the 9 AM overdue alert and its reminder
/// said "overdue"; one sent at 00:30 printed Nov 15, 29 days. Now a due date
/// is a day, and an invoice is late from the start of the day after it.
///
/// `nonisolated`: plain date arithmetic, used by the model and from tests.
nonisolated enum InvoiceTerms {
    /// How many days a new invoice gives to pay.
    static let days = 30

    /// The day `days` calendar days after `now`'s, at noon. Noon, not
    /// midnight: the same day still reads as that day a few time zones away.
    static func dueDate(from now: Date, days: Int = days, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        guard let day = calendar.date(byAdding: .day, value: days, to: start) else {
            return now.addingTimeInterval(TimeInterval(days) * 86_400)
        }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    /// Whether an invoice due on `due`'s day is late on `now`'s: from the
    /// start of the next day. Due today isn't late, whatever the time on
    /// `due` (a date picked on the builder keeps the time it was picked).
    static func isPastDue(_ due: Date, now: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: now) > calendar.startOfDay(for: due)
    }

    /// Whole calendar days late: 1 on the day after the due date. 0 when not late.
    static func daysLate(_ due: Date, now: Date, calendar: Calendar = .current) -> Int {
        guard isPastDue(due, now: now, calendar: calendar) else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: due),
                                           to: calendar.startOfDay(for: now)).day ?? 1
        return max(1, days)
    }
}
