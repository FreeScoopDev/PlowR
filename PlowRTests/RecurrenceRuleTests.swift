//
//  RecurrenceRuleTests.swift
//  PlowRTests
//

import Testing
import Foundation
@testable import PlowR

/// Repeating visits. The bugs these pin: Add Visit ignored the chosen weekdays,
/// a visit wrapping to the next week landed at midnight, every-2-weeks skipped
/// the week's other days, a series from the 31st drifted to the 28th, and
/// completing a visit duplicated the series' next one.
struct RecurrenceRuleTests {

    /// A fixed calendar, so the machine's time zone and locale don't matter.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let monThu: Set<Int> = [2, 5]      // 1 = Sunday

    // Weekly on Mon and Thu, first visit on a Wednesday (7 Oct 2026). The old
    // Add Visit rule stepped 7 days at a time: 52 Wednesdays.
    @Test func weeklyVisitsFallOnTheChosenDays() {
        let rule = RecurrenceRule(type: .weekly, weekdays: monThu)
        #expect(rule.occurrences(from: date(2026, 10, 7), limit: 5, calendar: calendar) ==
                [date(2026, 10, 7), date(2026, 10, 8), date(2026, 10, 12), date(2026, 10, 15), date(2026, 10, 19)])
    }

    // Thursday 9:00 → Monday 9:00. The old rule gave Monday 00:00, which then
    // showed as overdue all day.
    @Test func wrappingToNextWeekKeepsTheTimeOfDay() {
        let rule = RecurrenceRule(type: .weekly, weekdays: monThu)
        #expect(rule.next(after: date(2026, 10, 8, 9, 30), calendar: calendar) == date(2026, 10, 12, 9, 30))
    }

    // Every 2 weeks on Mon and Thu from a Monday: the old rule jumped straight to
    // the Monday two weeks on and skipped every Thursday.
    @Test func everyTwoWeeksKeepsTheWeeksOtherDays() {
        let rule = RecurrenceRule(type: .weekly, interval: 2, weekdays: monThu)
        #expect(rule.occurrences(from: date(2026, 10, 5), limit: 4, calendar: calendar) ==
                [date(2026, 10, 5), date(2026, 10, 8), date(2026, 10, 19), date(2026, 10, 22)])
    }

    // Weeks start on Sunday, as in the weekday picker, even where the device's
    // calendar starts them on Monday.
    @Test func theDevicesFirstWeekdayDoesNotMoveTheDays() {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let rule = RecurrenceRule(type: .weekly, weekdays: monThu)
        #expect(rule.occurrences(from: date(2026, 10, 7), limit: 5, calendar: mondayFirst) ==
                rule.occurrences(from: date(2026, 10, 7), limit: 5, calendar: calendar))
    }

    @Test func monthlyFromThe31stDoesNotDriftToThe28th() {
        let rule = RecurrenceRule(type: .monthly)
        #expect(rule.occurrences(from: date(2027, 1, 31), limit: 4, calendar: calendar) ==
                [date(2027, 1, 31), date(2027, 2, 28), date(2027, 3, 31), date(2027, 4, 30)])
    }

    @Test func aSeriesIsCreatedUpToItsLimitAndNoFurtherThanItsHorizon() {
        let daily = RecurrenceRule(type: .daily)
        #expect(daily.occurrences(from: date(2026, 10, 1), calendar: calendar).count == RecurrenceRule.upFrontLimit)

        // Every 30 months: nothing more within two years, just the first visit.
        let rare = RecurrenceRule(type: .monthly, interval: 30)
        let horizon = calendar.date(byAdding: RecurrenceRule.upFrontHorizon, to: date(2026, 10, 1))
        #expect(rare.occurrences(from: date(2026, 10, 1), horizon: horizon, calendar: calendar) == [date(2026, 10, 1)])
    }

    // The end date is a day: a 9:00 visit on it counts, whatever time the picker stored.
    @Test func theEndDateIncludesTheWholeDay() {
        let rule = RecurrenceRule(type: .weekly, endDate: date(2026, 10, 19, 0, 0))
        #expect(rule.occurrences(from: date(2026, 10, 5), calendar: calendar) ==
                [date(2026, 10, 5), date(2026, 10, 12), date(2026, 10, 19)])
        #expect(rule.next(after: date(2026, 10, 19), calendar: calendar) == nil)
    }

    // US clocks go back on 1 Nov 2026: the visit stays at 9:00 local time.
    @Test func daylightSavingKeepsTheClockTime() {
        let rule = RecurrenceRule(type: .weekly)
        let next = rule.next(after: date(2026, 10, 26), calendar: calendar)
        #expect(next == date(2026, 11, 2))
        #expect(next.map { calendar.component(.hour, from: $0) } == 9)
    }

    // Completing a visit adds the series' next one only if nothing is scheduled
    // after it. A series made up front already has it; adding it again was the
    // duplicate on every completion.
    @Test func completingAddsAVisitOnlyWhenTheSeriesHasRunOut() {
        let today = date(2026, 10, 5)
        #expect(!RecurrenceRule.shouldAddNext(afterCompleting: today, seriesDates: [date(2026, 10, 12)]))
        #expect(RecurrenceRule.shouldAddNext(afterCompleting: today, seriesDates: []))
        #expect(RecurrenceRule.shouldAddNext(afterCompleting: today, seriesDates: [date(2026, 9, 28)]))
    }
}

/// A visit added to continue a series carries everything the series has.
@MainActor
struct ScheduledVisitSeriesTests {

    @Test func theNextVisitCarriesTheSeriesDetails() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 7)))
        let visit = ScheduledVisit(operatorID: "op", clientID: "c1", clientName: "Pat",
                                   clientAddress: "1 Main St", scheduledDate: start)
        visit.isRecurring = true
        visit.recurrenceType = .weekly
        visit.recurrenceWeekdays = [2, 5]
        visit.visitReason = "Routine Visit"
        visit.expectedServiceIDs = ["svc-1", "svc-2"]
        visit.estimatedMinutes = 45
        visit.isAfterHours = true
        visit.afterHoursMultiplier = 1.75

        let next = try #require(visit.makeNextOccurrence(calendar: calendar))
        #expect(next.scheduledDate == calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 7)))
        #expect(next.seriesID == visit.seriesID)
        #expect(next.visitReason == "Routine Visit")
        #expect(next.expectedServiceIDs == ["svc-1", "svc-2"])
        #expect(next.estimatedMinutes == 45)
        #expect(next.isAfterHours && next.afterHoursMultiplier == 1.75)
        #expect(next.recurrenceWeekdays == [2, 5])
        #expect(next.status == .scheduled)
    }
}
