//
//  ExpenseSummaryTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Home → Expenses' summary: its periods (seasons too), spending by
/// category, distance, and income that is the Season Report's figure.
@MainActor
struct ExpenseSummaryTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let client: Client

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false
        client = Client(name: "Avery", phone: "", address: "1 Main St", operatorID: "op")
        container.mainContext.insert(client)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s)) ?? .distantPast
    }

    private func expense(_ amount: Double, _ category: ExpenseCategory, on day: Date, operatorID: String = "op") -> Expense {
        let expense = Expense(operatorID: operatorID, date: day, amount: amount, category: category)
        context.insert(expense)
        return expense
    }

    private func trip(_ distance: Double, _ unit: DistanceUnit, on day: Date, operatorID: String = "op") -> MileageEntry {
        let entry = MileageEntry(operatorID: operatorID, date: day, distance: distance, unit: unit)
        context.insert(entry)
        return entry
    }

    private func invoice(total: Double, sent: Date?, operatorID: String = "op") -> Proposal {
        let invoice = Proposal(operatorID: operatorID, client: client)
        invoice.invoiceNumber = "INV-\(UUID().uuidString.prefix(6))"
        invoice.invoiceSentAt = sent
        let item = ProposalLineItem(serviceName: "Service", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        context.insert(item)
        context.insert(invoice)
        invoice.lineItems = [item]
        return invoice
    }

    private func figures(expenses: [Expense] = [], trips: [MileageEntry] = [], documents: [Proposal] = [],
                         period: DateInterval, unit: DistanceUnit = .miles) -> ExpenseSummary.Figures {
        ExpenseSummary.figures(expenses: expenses, mileage: trips, documents: documents, operatorID: "op",
                               period: period, unit: unit)
    }

    // MARK: - Periods

    @Test func monthsAndYearsAreTheExistingPeriods() {
        let now = date(2026, 11, 15)
        let thisMonth = ExpenseSummary.Period.thisMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let billing = WorkBilling.Period.thisMonth.range(now: now, calendar: calendar)
        #expect(thisMonth.start == billing?.lowerBound)
        #expect(thisMonth.end == billing?.upperBound)
        let lastYear = ExpenseSummary.Period.lastYear.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let report = SeasonReport.Period.lastYear.interval(now: now, calendar: calendar)
        #expect(lastYear == report)
        let twelve = ExpenseSummary.Period.last12Months.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let reportTwelve = SeasonReport.Period.last12Months.interval(now: now, calendar: calendar)
        #expect(twelve == reportTwelve)
    }

    // An expense at midnight on the 1st is the new month's, not the old one's.
    @Test func anExpenseAtMidnightOnTheFirstIsThatMonths() {
        let now = date(2026, 11, 15)
        let first = expense(10, .fuel, on: date(2026, 11, 1, 0, 0, 0))
        let lastSecond = expense(4, .fuel, on: date(2026, 10, 31, 23, 59, 59))
        let thisMonth = ExpenseSummary.Period.thisMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let lastMonth = ExpenseSummary.Period.lastMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let this = figures(expenses: [first, lastSecond], period: thisMonth)
        let last = figures(expenses: [first, lastSecond], period: lastMonth)
        #expect(this.spent == 10)
        #expect(last.spent == 4)
        let newYear = expense(7, .other, on: date(2026, 1, 1, 0, 0, 0))
        let thisYear = ExpenseSummary.Period.thisYear.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let lastYear = ExpenseSummary.Period.lastYear.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let inThisYear = figures(expenses: [newYear], period: thisYear)
        let inLastYear = figures(expenses: [newYear], period: lastYear)
        #expect(inThisYear.spent == 7)
        #expect(inLastYear.spent == 0)
    }

    @Test func seasonsAreOfferedOnlyWithAStartMonth() {
        let unset = ExpenseSummary.Period.choices(seasonStartMonth: 0)
        #expect(unset.contains(.last12Months))
        #expect(!unset.contains(.thisSeason))
        #expect(!unset.contains(.lastSeason))
        let set = ExpenseSummary.Period.choices(seasonStartMonth: 11)
        #expect(set.contains(.thisSeason))
        #expect(set.contains(.lastSeason))
        #expect(!set.contains(.last12Months))
        let outOfRange = ExpenseSummary.Period.choices(seasonStartMonth: 13)
        #expect(outOfRange == unset)
        #expect(ExpenseSummary.Period.thisSeason.available(seasonStartMonth: 0) == .last12Months)
        #expect(ExpenseSummary.Period.last12Months.available(seasonStartMonth: 4) == .thisSeason)
        #expect(ExpenseSummary.Period.thisMonth.available(seasonStartMonth: 4) == .thisMonth)
    }

    @Test func aSeasonStartingThisMonthStartsOnItsFirst() {
        let now = date(2026, 11, 15)
        let season = ExpenseSummary.season(containing: now, startMonth: 11, calendar: calendar)
        #expect(season?.start == date(2026, 11, 1, 0))
        #expect(season?.end == date(2027, 11, 1, 0))
        let onTheFirst = ExpenseSummary.season(containing: date(2026, 11, 1, 0), startMonth: 11, calendar: calendar)
        #expect(onTheFirst?.start == date(2026, 11, 1, 0))
        let dayBefore = ExpenseSummary.season(containing: date(2026, 10, 31, 23, 59, 59), startMonth: 11, calendar: calendar)
        #expect(dayBefore?.start == date(2025, 11, 1, 0))
    }

    @Test func seasonsWrapTheNewYear() {
        // A December start, in January: the season began last December.
        let january = date(2027, 1, 10)
        let thisSeason = ExpenseSummary.Period.thisSeason.interval(now: january, seasonStartMonth: 12, calendar: calendar)
        #expect(thisSeason.start == date(2026, 12, 1, 0))
        #expect(thisSeason.end == date(2027, 12, 1, 0))
        let lastSeason = ExpenseSummary.Period.lastSeason.interval(now: january, seasonStartMonth: 12, calendar: calendar)
        #expect(lastSeason.start == date(2025, 12, 1, 0))
        #expect(lastSeason.end == date(2026, 12, 1, 0))
        // A January start, on December 31: this year's January.
        let december = date(2026, 12, 31, 23, 59, 59)
        let janSeason = ExpenseSummary.Period.thisSeason.interval(now: december, seasonStartMonth: 1, calendar: calendar)
        #expect(janSeason.start == date(2026, 1, 1, 0))
        #expect(janSeason.end == date(2027, 1, 1, 0))
        // An expense on December 1 at midnight is the December season's.
        let first = expense(30, .materials, on: date(2026, 12, 1, 0, 0, 0))
        let inThis = figures(expenses: [first], period: thisSeason)
        let inLast = figures(expenses: [first], period: lastSeason)
        #expect(inThis.spent == 30)
        #expect(inLast.spent == 0)
    }

    @Test func aSeasonWithNoStartMonthIsTheLast12Months() {
        let now = date(2026, 11, 15)
        #expect(ExpenseSummary.season(containing: now, startMonth: 0, calendar: calendar) == nil)
        #expect(ExpenseSummary.season(containing: now, startMonth: 13, calendar: calendar) == nil)
        let season = ExpenseSummary.Period.thisSeason.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let twelve = SeasonReport.Period.last12Months.interval(now: now, calendar: calendar)
        #expect(season == twelve)
    }

    @Test func theSeasonMonthIsReadThroughBusinessProfiles() {
        let profile = BusinessProfile(operatorID: "op")
        profile.seasonStartMonth = 14
        let month = BusinessProfiles.seasonStartMonth(profile)
        let choices = ExpenseSummary.Period.choices(seasonStartMonth: month)
        #expect(!choices.contains(.thisSeason))
    }

    // MARK: - Figures

    @Test func spendingIsByCategoryToTheCent() {
        let now = date(2026, 11, 15)
        let period = ExpenseSummary.Period.thisMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let fuelA = expense(0.105, .fuel, on: date(2026, 11, 2))
        let fuelB = expense(0.105, .fuel, on: date(2026, 11, 3))
        let gear = expense(120.40, .equipment, on: date(2026, 11, 4))
        let result = figures(expenses: [gear, fuelA, fuelB], period: period)
        let expected: [ExpenseSummary.CategoryTotal] = [
            ExpenseSummary.CategoryTotal(category: .fuel, amount: 0.22),
            ExpenseSummary.CategoryTotal(category: .equipment, amount: 120.40)
        ]
        #expect(result.byCategory == expected)                // materials and other left out
        #expect(result.spent == 120.62)
        #expect(result.spent == Expenses.total([gear, fuelA, fuelB]))
    }

    @Test func incomeIsMoneyReceivedInThePeriod() {
        let now = date(2026, 11, 15)
        let period = ExpenseSummary.Period.thisMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        // Partly paid: one payment before the period, one in it.
        let partial = invoice(total: 100, sent: date(2026, 10, 1))
        Payments.record(10, method: "", receivedAt: date(2026, 10, 20), on: partial, in: context, now: now)
        Payments.record(40.25, method: "", receivedAt: date(2026, 11, 5), on: partial, in: context, now: now)
        // Marked paid with no payments kept: all of it, on that day.
        let markedPaid = invoice(total: 50, sent: date(2026, 11, 2))
        markedPaid.invoicePaidAt = date(2026, 11, 6)
        // A draft nobody has seen, worth 500: owes nothing received.
        let draft = invoice(total: 500, sent: nil)
        // A void invoice marked paid: its "paid" went to its revision.
        let void = invoice(total: 80, sent: date(2026, 11, 1))
        void.invoicePaidAt = date(2026, 11, 7)
        void.voidedAt = date(2026, 11, 8)
        let documents = [partial, markedPaid, draft, void]
        let result = figures(documents: documents, period: period)
        let received = Payments.received(documents, in: period)
        #expect(result.income == received)
        #expect(result.income == 90.25)
    }

    @Test func anotherBusinessIsLeftOut() {
        let now = date(2026, 11, 15)
        let period = ExpenseSummary.Period.thisMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let mine = expense(20, .fuel, on: date(2026, 11, 2))
        let theirs = expense(999, .fuel, on: date(2026, 11, 2), operatorID: "other")
        let myTrip = trip(5, .miles, on: date(2026, 11, 2))
        let theirTrip = trip(70, .miles, on: date(2026, 11, 2), operatorID: "other")
        let myInvoice = invoice(total: 60, sent: date(2026, 11, 1))
        myInvoice.invoicePaidAt = date(2026, 11, 3)
        let theirInvoice = invoice(total: 700, sent: date(2026, 11, 1), operatorID: "other")
        theirInvoice.invoicePaidAt = date(2026, 11, 3)
        let result = figures(expenses: [mine, theirs], trips: [myTrip, theirTrip],
                             documents: [myInvoice, theirInvoice], period: period)
        #expect(result.spent == 20)
        #expect(result.distance == 5)
        #expect(result.income == 60)
        #expect(result.net == 40)
    }

    @Test func aLossIsANegativeNet() {
        let now = date(2026, 11, 15)
        let period = ExpenseSummary.Period.thisMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let salt = expense(75.30, .materials, on: date(2026, 11, 2))
        let paid = invoice(total: 50.10, sent: date(2026, 11, 1))
        paid.invoicePaidAt = date(2026, 11, 3)
        let result = figures(expenses: [salt], documents: [paid], period: period)
        #expect(result.net == -25.2)
        let nothing = figures(period: period)
        #expect(nothing.net == 0)
        #expect(nothing.byCategory.isEmpty)
    }

    @Test func distanceAddsMixedUnitsInTheUnitAsked() {
        let now = date(2026, 11, 15)
        let period = ExpenseSummary.Period.thisMonth.interval(now: now, seasonStartMonth: 0, calendar: calendar)
        let miles = trip(10, .miles, on: date(2026, 11, 2))
        let kilometers = trip(16.09344, .kilometers, on: date(2026, 11, 3))
        let old = trip(100, .miles, on: date(2026, 10, 3))
        let inMiles = figures(trips: [miles, kilometers, old], period: period, unit: .miles)
        let inKilometers = figures(trips: [miles, kilometers, old], period: period, unit: .kilometers)
        #expect(abs(inMiles.distance - 20) < 0.0001)
        #expect(abs(inKilometers.distance - 32.18688) < 0.0001)
    }
}
