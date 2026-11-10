import Foundation
import SwiftData

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
/// How long a new invoice gives is the business's choice (Business Profile,
/// Payment Terms, 1.9 review): due on receipt, or net 7 to 60 days. Never
/// chosen, it's 30, the rule before there was a choice. The choice sets the
/// due date of an invoice when it's made; a saved invoice keeps the date it
/// has, whatever the profile says later, and its PDF states the terms from
/// its own dates (`statedTerms`).
///
/// `nonisolated`: plain date arithmetic, used by the model and from tests.
nonisolated enum InvoiceTerms {
    /// How many days a new invoice gives to pay when the business never chose.
    static let days = 30

    /// The terms a business can choose, in days: 0 is due on receipt.
    static let choices = [0, 7, 15, 30, 45, 60]

    /// The days a stored choice gives: 30 for none (never chosen, or a
    /// record from an older build) and for a value below 0.
    static func days(stored: Int?) -> Int {
        guard let stored, stored >= 0 else { return days }
        return stored
    }

    /// The business's terms, in days.
    @MainActor
    static func days(for profile: BusinessProfile?) -> Int {
        days(stored: profile?.paymentTermsDays)
    }

    /// "Due on receipt" for 0 days, "Net 15" for 15.
    static func name(days: Int) -> String {
        days <= 0 ? "Due on receipt" : "Net \(days)"
    }

    /// A new invoice's due date, made `now`, on `profile`'s terms.
    @MainActor
    static func dueDate(from now: Date, profile: BusinessProfile?, calendar: Calendar = .current) -> Date {
        dueDate(from: now, days: days(for: profile), calendar: calendar)
    }

    /// A new invoice's due date, made `now`, on the terms of the business
    /// `operatorID` (its profile found by BusinessProfiles.current). Every
    /// place a new invoice gets a due date comes here.
    @MainActor
    static func dueDate(from now: Date, operatorID: String, in context: ModelContext) -> Date {
        let profiles = (try? context.fetch(FetchDescriptor<BusinessProfile>())) ?? []
        return dueDate(from: now, profile: BusinessProfiles.current(profiles, operatorID: operatorID))
    }

    /// The terms a document states beside its due date, from its own dates
    /// (never the profile's choice now, which may have changed since it was
    /// made): due on or before the day it's dated, "Due on receipt"; exactly
    /// 7, 15, 30, 45 or 60 days after, "Net N"; anything else, nil (a date
    /// picked by hand states no terms).
    static func statedTerms(issued: Date, due: Date, calendar: Calendar = .current) -> String? {
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: issued),
                                          to: calendar.startOfDay(for: due)).day ?? 0
        if gap <= 0 { return name(days: 0) }
        return choices.contains(gap) ? name(days: gap) : nil
    }

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
