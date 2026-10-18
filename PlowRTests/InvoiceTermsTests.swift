import Foundation
import Testing
@testable import PlowR

/// A due date is a calendar day, and an invoice is late from the start of
/// the next one (Joe, 2026-10-18). It used to be "now + 720 hours": late an
/// hour early across the November clock change, and 29 days for an invoice
/// sent just after midnight.
struct InvoiceTermsTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .distantPast
    }

    func day(_ date: Date) -> DateComponents { calendar.dateComponents([.year, .month, .day], from: date) }

    @Test func thirtyCalendarDaysWhateverTheTime() {
        // Sent at 2 pm on Oct 17: due Nov 16, across the clock change.
        let afternoon = InvoiceTerms.dueDate(from: date(2026, 10, 17, 14), calendar: calendar)
        #expect(day(afternoon) == DateComponents(year: 2026, month: 11, day: 16))
        // Sent at 00:30: still Nov 16, not Nov 15.
        let justAfterMidnight = InvoiceTerms.dueDate(from: date(2026, 10, 17, 0, 30), calendar: calendar)
        #expect(day(justAfterMidnight) == DateComponents(year: 2026, month: 11, day: 16))
        // And at 11:59 pm.
        #expect(day(InvoiceTerms.dueDate(from: date(2026, 10, 17, 23, 59), calendar: calendar))
                == DateComponents(year: 2026, month: 11, day: 16))
        // Noon, so the day still reads the same a few time zones away.
        #expect(calendar.component(.hour, from: afternoon) == 12)
        // Across the spring clock change too.
        #expect(day(InvoiceTerms.dueDate(from: date(2027, 2, 20, 9), calendar: calendar))
                == DateComponents(year: 2027, month: 3, day: 22))
    }

    @Test func dueTodayIsNotLate() {
        let due = InvoiceTerms.dueDate(from: date(2026, 10, 17, 14), calendar: calendar)    // Nov 16
        #expect(!InvoiceTerms.isPastDue(due, now: date(2026, 11, 16, 0, 1), calendar: calendar))
        #expect(!InvoiceTerms.isPastDue(due, now: date(2026, 11, 16, 13), calendar: calendar))
        #expect(!InvoiceTerms.isPastDue(due, now: date(2026, 11, 16, 23, 59), calendar: calendar))
        #expect(InvoiceTerms.isPastDue(due, now: date(2026, 11, 17, 0, 0), calendar: calendar))
        #expect(InvoiceTerms.daysLate(due, now: date(2026, 11, 16, 23, 59), calendar: calendar) == 0)
        #expect(InvoiceTerms.daysLate(due, now: date(2026, 11, 17, 0, 0), calendar: calendar) == 1)
        #expect(InvoiceTerms.daysLate(due, now: date(2026, 12, 16, 9), calendar: calendar) == 30)
    }

    // A date picked on the builder keeps the time it was picked; its day is what counts.
    @Test func aPickedDateCountsByItsDay() {
        let picked = date(2026, 11, 16, 23, 30)
        #expect(!InvoiceTerms.isPastDue(picked, now: date(2026, 11, 16, 23, 45), calendar: calendar))
        let early = date(2026, 11, 16, 0, 5)
        #expect(!InvoiceTerms.isPastDue(early, now: date(2026, 11, 16, 22), calendar: calendar))
        #expect(InvoiceTerms.isPastDue(early, now: date(2026, 11, 17, 0, 1), calendar: calendar))
    }

    // An invoice made before this change (due at the time it was sent) is
    // late from the day after the date it shows, as the PDF says.
    @Test func anOlderInvoiceIsLateFromTheDayAfterItsDate() {
        let old = date(2026, 10, 17, 14).addingTimeInterval(30 * 86_400)              // Nov 16, 1 pm EST
        #expect(day(old) == DateComponents(year: 2026, month: 11, day: 16))
        #expect(!InvoiceTerms.isPastDue(old, now: date(2026, 11, 16, 20), calendar: calendar))
        #expect(InvoiceTerms.isPastDue(old, now: date(2026, 11, 17, 8), calendar: calendar))
    }
}
