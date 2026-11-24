//
//  ExpensesTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Home → Expenses: reading an amount, the total, and what "What" suggests.
@MainActor
struct ExpensesTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false
    }

    private let us = Locale(identifier: "en_US")
    private let germany = Locale(identifier: "de_DE")

    @Test func amountsAreReadToTheCent() {
        #expect(Expenses.amount(typed: "45.20", locale: us) == 45.2)
        #expect(Expenses.amount(typed: " 12 ", locale: us) == 12)
        #expect(Expenses.amount(typed: "19.999", locale: us) == 20)
        #expect(Expenses.amount(typed: "0.105", locale: us) == 0.11)
    }

    @Test func aDecimalCommaIsReadWhereTheRegionWritesOne() {
        #expect(Expenses.amount(typed: "12,50", locale: germany) == 12.5)
        // In the US a comma separates thousands, so it isn't guessed at.
        #expect(Expenses.amount(typed: "12,50", locale: us) == nil)
    }

    @Test func anAmountThatCantBeSavedIsRefused() {
        for typed in ["", "  ", "abc", "12.5.1", "0", "0.00", "0.004", "-5", "nan", "inf", "2000000000"] {
            #expect(Expenses.amount(typed: typed, locale: us) == nil, "\(typed)")
        }
    }

    @Test func quantitiesAreOptional() {
        #expect(Expenses.quantity(typed: "", locale: us) == 0)
        #expect(Expenses.quantity(typed: "2,5", locale: germany) == 2.5)
        #expect(Expenses.quantity(typed: "lots", locale: us) == nil)
        #expect(Expenses.quantity(typed: "-1", locale: us) == nil)
    }

    // Kept to the places the editor shows, so reopening an expense reads
    // back what was stored and Cancel doesn't ask to discard a change.
    @Test func aQuantityIsKeptAsItIsShown() throws {
        let stored = try #require(Expenses.quantity(typed: "2.123456", locale: us))
        #expect(stored == 2.1235)
        let shown: String = DecimalText.trimmed(stored)
        let reread: Double? = Expenses.quantity(typed: shown, locale: us)
        #expect(reread == stored)
    }

    @Test func theSeasonMonthIsOneToTwelveOrNotSet() {
        let profile = BusinessProfile(operatorID: "op")
        context.insert(profile)
        for (stored, read) in [(0, 0), (1, 1), (12, 12), (13, 0), (-1, 0)] {
            profile.seasonStartMonth = stored
            #expect(BusinessProfiles.seasonStartMonth(profile) == read, "\(stored)")
        }
    }

    @Test func theSeasonPickerHasTwelveGregorianMonths() {
        let english: [String] = BusinessProfiles.seasonMonthNames(locale: Locale(identifier: "en_US"))
        #expect(english.count == 12)
        #expect(english.first == "January")
        // A region whose calendar isn't Gregorian still gets twelve months,
        // in its own language.
        let hebrew: [String] = BusinessProfiles.seasonMonthNames(locale: Locale(identifier: "he_IL@calendar=hebrew"))
        #expect(hebrew.count == 12)
        let french: [String] = BusinessProfiles.seasonMonthNames(locale: Locale(identifier: "fr_FR"))
        #expect(french.first == "janvier")
    }

    @Test func theTotalIsToTheCent() {
        let amounts = [0.1, 0.2, 45.2, 19.99]
        let expenses = amounts.map { Expense(operatorID: "op", amount: $0) }
        expenses.forEach { context.insert($0) }
        #expect(Expenses.total(expenses) == 65.49)
        #expect(Expenses.total([]) == 0)
    }

    private func expense(_ item: String, operatorID: String = "op", daysAgo: Double) -> Expense {
        let expense = Expense(operatorID: operatorID, date: Date(timeIntervalSinceNow: -daysAgo * 86_400), amount: 1)
        expense.item = item
        context.insert(expense)
        return expense
    }

    @Test func suggestionsAreThisOperatorsMostRecentFirstEachOnce() {
        let expenses = [
            expense("mulch", daysAgo: 30),
            expense("Mulch", daysAgo: 2),
            expense("Seed", daysAgo: 5),
            expense("Marking paint", daysAgo: 10),
            expense("", daysAgo: 1),
            expense("Mixed gas", operatorID: "someone else", daysAgo: 0),
        ]
        #expect(Expenses.itemSuggestions(expenses, operatorID: "op", prefix: "")
                == ["Mulch", "Seed", "Marking paint"])
        #expect(Expenses.itemSuggestions(expenses, operatorID: "op", prefix: "m") == ["Mulch", "Marking paint"])
        // What's typed already isn't offered again.
        #expect(Expenses.itemSuggestions(expenses, operatorID: "op", prefix: "MULCH") == [])
    }

    @Test func listsAreGroupedByMonthNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        func on(_ month: Int, _ day: Int) throws -> Expense {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9)))
            let expense = Expense(operatorID: "op", date: date, amount: Double(day))
            context.insert(expense)
            return expense
        }
        let oct = try on(10, 31), novEarly = try on(11, 1), novLate = try on(11, 24)
        let groups = Expenses.byMonth([novEarly, oct, novLate], date: \.date, made: \.createdAt, calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups[0].items.map(\.amount) == [24, 1])
        #expect(groups[1].items.map(\.amount) == [31])
        #expect(calendar.component(.month, from: groups[0].month) == 11)
    }

    @Test func anExpenseIsNamedByWhatWasBoughtOrItsCategory() {
        let expense = Expense(operatorID: "op", amount: 45.2, category: .equipment)
        context.insert(expense)
        #expect(Expenses.name(of: expense) == "Equipment & Repairs")
        expense.item = "Blade"
        #expect(Expenses.deleteTitle(for: expense) == "Delete \u{201C}Blade\u{201D}, \(Money.text(45.2))?")
        expense.categoryRaw = "from a newer PlowR"
        #expect(expense.category == .other)
    }
}

/// The mileage log: units and totals. Distances are typed, never measured.
@MainActor
struct MileageTests {
    @Test(arguments: [("en_US", DistanceUnit.miles), ("en_GB", .miles), ("de_DE", .kilometers), ("fr_CA", .kilometers)])
    func theDefaultUnitFollowsTheRegion(_ identifier: String, _ unit: DistanceUnit) {
        #expect(DistanceUnit.default(for: Locale(identifier: identifier)) == unit)
    }

    @Test func aMixedLogTotalsInEitherUnit() throws {
        let container = try ModelContainer(for: Schema(PlowRApp.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false
        let entries = [MileageEntry(operatorID: "op", distance: 10, unit: .miles),
                       MileageEntry(operatorID: "op", distance: 16.09344, unit: .kilometers)]
        entries.forEach { container.mainContext.insert($0) }
        #expect(abs(Mileage.total(entries, in: .miles) - 20) < 0.0001)
        #expect(abs(Mileage.total(entries, in: .kilometers) - 32.18688) < 0.0001)
        #expect(Mileage.total([], in: .miles) == 0)
    }

    @Test func aDistanceShowsInItsOwnUnit() {
        // Never converted to the region's unit. (Spaces as plain spaces:
        // the formatter may use a no-break one.)
        func text(_ distance: Double, _ unit: DistanceUnit, _ locale: String) -> String {
            Mileage.text(distance, unit: unit, locale: Locale(identifier: locale))
                .replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(text(12.5, .miles, "de_DE") == "12,5 mi")
        #expect(text(30, .kilometers, "en_US") == "30 km")
        #expect(text(30, .miles, "en_GB") == "30 mi")
    }

    @Test func aTypedDistanceMustBeAboveZero() {
        let us = Locale(identifier: "en_US")
        #expect(Mileage.distance(typed: "12.5", locale: us) == 12.5)
        #expect(Mileage.distance(typed: "12,5", locale: Locale(identifier: "de_DE")) == 12.5)
        for typed in ["", "0", "-3", "far", "200000", "0.004"] {
            #expect(Mileage.distance(typed: typed, locale: us) == nil, "\(typed)")
        }
    }

    // Kept to the two places the editor shows, so reopening a trip reads
    // back what was stored and Cancel doesn't ask to discard a change.
    @Test func aDistanceIsKeptToTwoPlaces() throws {
        let us = Locale(identifier: "en_US")
        let stored = try #require(Mileage.distance(typed: "12.345678", locale: us))
        #expect(stored == 12.35)
        let shown: String = DecimalText.trimmed(stored, places: 2)
        let reread: Double? = Mileage.distance(typed: shown, locale: us)
        #expect(reread == stored)
    }
}
