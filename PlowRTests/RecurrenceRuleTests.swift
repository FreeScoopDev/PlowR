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

    private func time(_ d: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? -1, c.minute ?? -1)
    }

    private let monThu: Set<Int> = [2, 5]      // 1 = Sunday

    // Weekly on Mon and Thu, first visit on a Wednesday (7 Oct 2026). The old
    // Add Visit rule stepped 7 days at a time: 52 Wednesdays.
    @Test func weeklyVisitsFallOnTheChosenDays() {
        let rule = RecurrenceRule(type: .weekly, weekdays: monThu)
        #expect(rule.occurrences(from: date(2026, 10, 7), limit: 5, calendar: calendar) ==
                [date(2026, 10, 7), date(2026, 10, 8), date(2026, 10, 12), date(2026, 10, 15), date(2026, 10, 19)])
    }

    // Thursday 9:30 → Monday 9:30. The old rule gave Monday 00:00, which then
    // showed as overdue all day.
    @Test func wrappingToNextWeekKeepsTheTimeOfDay() {
        let rule = RecurrenceRule(type: .weekly, weekdays: monThu)
        #expect(rule.occurrences(from: date(2026, 10, 8, 9, 30), limit: 2, calendar: calendar) ==
                [date(2026, 10, 8, 9, 30), date(2026, 10, 12, 9, 30)])
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
        let done = [date(2026, 10, 5), date(2026, 10, 12)].map { RecurrenceRule.SeriesVisit(date: $0, isScheduled: false) }
        #expect(rule.continuationDate(afterCompleting: date(2026, 10, 19), series: done, calendar: calendar) == nil)
    }

    // US clocks go back on 1 Nov 2026: the visit stays at 9:00 local time.
    @Test func daylightSavingKeepsTheClockTime() {
        let rule = RecurrenceRule(type: .weekly)
        #expect(rule.occurrences(from: date(2026, 10, 26), limit: 2, calendar: calendar) ==
                [date(2026, 10, 26), date(2026, 11, 2)])
    }

    // Sun and Wed at 2:30 AM. 2:30 doesn't exist on 14 Mar 2027 (clocks jump to
    // 3:00); every later visit must be back at 2:30, not stuck at 3:00.
    @Test func weekdaySeriesKeepTheirTimeAfterADaylightSavingJump() {
        let rule = RecurrenceRule(type: .weekly, weekdays: [1, 4])
        let dates = rule.occurrences(from: date(2027, 3, 3, 2, 30), limit: 8, calendar: calendar)
        #expect(dates.count == 8)
        let transitionDay = calendar.startOfDay(for: date(2027, 3, 14, 12))
        for d in dates where calendar.startOfDay(for: d) != transitionDay {
            #expect(time(d) == "02:30", "\(d)")
        }
    }

    // MARK: - Continuing a series after a visit is completed

    private typealias Visit = RecurrenceRule.SeriesVisit

    // A series made up front already has its next visit: adding one again was
    // the duplicate on every completion.
    @Test func aSeriesWithVisitsStillScheduledGetsNothingNew() {
        let rule = RecurrenceRule(type: .weekly)
        #expect(rule.continuationDate(afterCompleting: date(2026, 10, 5),
                                      series: [Visit(date: date(2026, 10, 12), isScheduled: true)],
                                      calendar: calendar) == nil)
    }

    @Test func aSeriesThatHasRunOutGetsItsNextVisit() {
        let rule = RecurrenceRule(type: .weekly)
        let done = [Visit(date: date(2026, 10, 5), isScheduled: false), Visit(date: date(2026, 10, 12), isScheduled: false)]
        #expect(rule.continuationDate(afterCompleting: date(2026, 10, 19), series: done, calendar: calendar) ==
                date(2026, 10, 26))
    }

    // Skipping the last visit and completing the one before must neither end the
    // series nor re-create the skipped date.
    @Test func aSkippedLastVisitDoesNotEndOrRepeatTheSeries() {
        let rule = RecurrenceRule(type: .weekly)
        let series = [Visit(date: date(2026, 10, 5), isScheduled: false),
                      Visit(date: date(2026, 10, 19), isScheduled: false)]     // skipped
        #expect(rule.continuationDate(afterCompleting: date(2026, 10, 12), series: series, calendar: calendar) ==
                date(2026, 10, 26))
    }

    // Continuing a series counts from its first visit: the 31st stays the 31st.
    @Test func aContinuedMonthlySeriesKeepsItsDayOfMonth() {
        let rule = RecurrenceRule(type: .monthly)
        #expect(rule.continuationDate(afterCompleting: date(2027, 2, 28),
                                      series: [Visit(date: date(2027, 1, 31), isScheduled: false)],
                                      calendar: calendar) == date(2027, 3, 31))
    }

    // "This & All Future" moved a daily series from 9:00 to 7:00 from its tenth
    // visit on. Counting from the first visit would add a 9:00 visit on the same
    // day as the 7:00 one just completed.
    @Test func aTimeChangeForAllFutureVisitsIsKept() {
        let rule = RecurrenceRule(type: .daily)
        var series = (0..<52).map { k -> Visit in
            let day = calendar.date(byAdding: .day, value: k, to: date(2026, 10, 1))!
            return Visit(date: calendar.date(bySettingHour: k < 9 ? 9 : 7, minute: 0, second: 0, of: day)!,
                         isScheduled: false)
        }
        let last = series.removeLast()
        #expect(last.date == date(2026, 11, 21, 7))
        #expect(rule.continuationDate(afterCompleting: last.date, series: series, calendar: calendar) ==
                date(2026, 11, 22, 7))
    }

    // "This Visit Only" moved the first Monday visit to a Tuesday at 10:00: the
    // series stays on Mondays at 9:00.
    @Test func aMovedFirstVisitDoesNotMoveTheSeries() {
        let rule = RecurrenceRule(type: .weekly)
        var series = (0..<52).map { k in
            Visit(date: calendar.date(byAdding: .day, value: 7 * k, to: date(2026, 10, 5))!, isScheduled: false)
        }
        series[0].date = date(2026, 10, 6, 10)
        let last = series.removeLast()
        #expect(last.date == date(2027, 9, 27))
        #expect(rule.continuationDate(afterCompleting: last.date, series: series, calendar: calendar) ==
                date(2027, 10, 4))
    }

    // The last Monday visit of a batch was done on Tuesday at 14:00 (rained out):
    // the series carries on on Mondays at 9:00.
    @Test func aOneOffMoveOfTheLastVisitDoesNotMoveTheSeries() {
        let rule = RecurrenceRule(type: .weekly)
        var series = (0..<52).map { k in
            Visit(date: calendar.date(byAdding: .day, value: 7 * k, to: date(2026, 10, 5))!, isScheduled: false)
        }
        var last = series.removeLast()
        last.date = date(2027, 9, 28, 14)
        #expect(rule.continuationDate(afterCompleting: last.date, series: series, calendar: calendar) ==
                date(2027, 10, 4))
    }

    // A new time the last two visits already have is the series' time now.
    @Test func aNewTimeOnTheLastVisitsCarriesOn() {
        let rule = RecurrenceRule(type: .daily)
        let series = [date(2026, 10, 1, 9), date(2026, 10, 2, 9), date(2026, 10, 3, 7)]
            .map { Visit(date: $0, isScheduled: false) }
        #expect(rule.continuationDate(afterCompleting: date(2026, 10, 4, 7), series: series, calendar: calendar) ==
                date(2026, 10, 5, 7))
    }

    // ...and its time of day, even from a visit that landed at 3:00 on the jump day.
    @Test func aContinuedWeekdaySeriesKeepsItsTime() {
        let rule = RecurrenceRule(type: .weekly, weekdays: [1, 4])
        let earlier = [date(2027, 3, 3, 2, 30), date(2027, 3, 7, 2, 30), date(2027, 3, 10, 2, 30)]
            .map { Visit(date: $0, isScheduled: false) }
        let next = rule.continuationDate(afterCompleting: date(2027, 3, 14, 3, 0), series: earlier, calendar: calendar)
        #expect(next == date(2027, 3, 17, 2, 30))
    }
}

/// Continuing a real series: which visits count, and what the new one carries.
@MainActor
struct ScheduledVisitSeriesTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func at(_ m: Int, _ d: Int, _ h: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
    }

    private func repeatingVisit(on date: Date, series: String = "series-a") -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: "c1", clientName: "Pat",
                                   clientAddress: "1 Main St", scheduledDate: date)
        visit.isRecurring = true
        visit.recurrenceType = .weekly
        visit.recurrenceInterval = 2
        visit.recurrenceWeekdays = [2, 5]
        visit.recurrenceEndDate = at(12, 31)
        visit.notes = "Gate code 1234"
        visit.visitReason = "Routine Visit"
        visit.expectedServiceIDs = ["svc-1", "svc-2"]
        visit.estimatedMinutes = 45
        visit.isAfterHours = true
        visit.afterHoursMultiplier = 1.75
        visit.seriesID = series
        return visit
    }

    @Test func theNextVisitCarriesEverythingTheSeriesHas() throws {
        let completed = repeatingVisit(on: at(10, 8))              // Thursday
        completed.status = .completed
        let next = try #require(completed.continuation(among: [completed], calendar: calendar))
        #expect(next.scheduledDate == at(10, 19))                  // Monday two weeks on
        #expect(next.status == .scheduled)
        #expect(next.seriesID == "series-a")
        #expect(next.isRecurring)
        #expect(next.recurrenceType == .weekly)
        #expect(next.recurrenceInterval == 2)
        #expect(next.recurrenceWeekdays == [2, 5])
        #expect(next.recurrenceEndDate == at(12, 31))
        #expect(next.notes == "Gate code 1234")
        #expect(next.visitReason == "Routine Visit")
        #expect(next.expectedServiceIDs == ["svc-1", "svc-2"])
        #expect(next.estimatedMinutes == 45)
        #expect(next.isAfterHours && next.afterHoursMultiplier == 1.75)
    }

    // Another series' visit for the same client doesn't stop this one continuing.
    @Test func onlyThisSeriesVisitsCount() {
        let completed = repeatingVisit(on: at(10, 8))
        let otherSeries = repeatingVisit(on: at(10, 30), series: "series-b")      // same client, still scheduled
        #expect(completed.continuation(among: [completed, otherSeries], calendar: calendar) != nil)
        let sameSeries = repeatingVisit(on: at(10, 12))
        #expect(completed.continuation(among: [completed, sameSeries], calendar: calendar) == nil)
    }

    // A later visit in the series that was skipped (or cancelled) isn't "still to
    // do": it must not stop the series continuing.
    @Test func aSkippedLaterVisitDoesNotStopTheSeries() {
        let completed = repeatingVisit(on: at(10, 8))
        let skipped = repeatingVisit(on: at(10, 12))
        skipped.status = .skipped
        let next = completed.continuation(among: [completed, skipped], calendar: calendar)
        #expect(next?.scheduledDate == at(10, 15))       // the chosen Thursday after the skipped Monday
    }

    @Test func aOneOffVisitIsNeverContinued() {
        let visit = repeatingVisit(on: at(10, 8))
        visit.isRecurring = false
        #expect(visit.continuation(among: [visit], calendar: calendar) == nil)
    }
}
