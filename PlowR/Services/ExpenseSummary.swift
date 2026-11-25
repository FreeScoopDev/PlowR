import Foundation

/// The summary at the top of Home → Expenses: for a period, what was spent
/// by category, how far the business drove, the money that came in and
/// what's left. Income is `Payments.received(_:in:)`, the Season Report's
/// figure, never a sum of invoice totals. Viewing it is free.
enum ExpenseSummary {
    /// The periods the summary can cover. The month cases are
    /// `WorkBilling.Period`'s and the year and 12-month cases
    /// `SeasonReport.Period`'s, so a month or a year here is the same dates
    /// as there. The season cases need Business Profile's Season Starts.
    enum Period: String, CaseIterable, Identifiable {
        case thisMonth, lastMonth, thisSeason, lastSeason, last12Months, thisYear, lastYear

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thisMonth: "This Month"
            case .lastMonth: "Last Month"
            case .thisSeason: "This Season"
            case .lastSeason: "Last Season"
            case .last12Months: "Last 12 Months"
            case .thisYear: "This Year"
            case .lastYear: "Last Year"
            }
        }

        var isSeason: Bool { self == .thisSeason || self == .lastSeason }

        /// The menu's periods: the two seasons when a season start month is
        /// set (1–12, as `BusinessProfiles.seasonStartMonth` reads it), Last
        /// 12 Months in their place when not.
        static func choices(seasonStartMonth: Int) -> [Period] {
            let seasons = (1...12).contains(seasonStartMonth)
            return allCases.filter { seasons ? $0 != .last12Months : !$0.isSeason }
        }

        /// This period if the menu offers it, else its stand-in: a season
        /// chosen before Season Starts was cleared reads as Last 12 Months,
        /// and Last 12 Months as This Season once it's set.
        func available(seasonStartMonth: Int) -> Period {
            let choices = Self.choices(seasonStartMonth: seasonStartMonth)
            if choices.contains(self) { return self }
            return isSeason ? .last12Months : .thisSeason
        }

        /// Its dates, from the start up to but not including the end. A
        /// season with no start month set covers Last 12 Months.
        func interval(now: Date, seasonStartMonth: Int, calendar: Calendar = .current) -> DateInterval {
            switch self {
            case .thisMonth, .lastMonth:
                let billing: WorkBilling.Period = self == .thisMonth ? .thisMonth : .lastMonth
                guard let range = billing.range(now: now, calendar: calendar) else {
                    return DateInterval(start: now, duration: 0)
                }
                return DateInterval(start: range.lowerBound, end: range.upperBound)
            case .last12Months:
                return SeasonReport.Period.last12Months.interval(now: now, calendar: calendar)
            case .thisYear:
                return SeasonReport.Period.thisYear.interval(now: now, calendar: calendar)
            case .lastYear:
                return SeasonReport.Period.lastYear.interval(now: now, calendar: calendar)
            case .thisSeason, .lastSeason:
                guard let season = ExpenseSummary.season(containing: now, startMonth: seasonStartMonth,
                                                         calendar: calendar) else {
                    return SeasonReport.Period.last12Months.interval(now: now, calendar: calendar)
                }
                if self == .thisSeason { return season }
                var gregorian = Calendar(identifier: .gregorian)
                gregorian.timeZone = calendar.timeZone
                let start = gregorian.date(byAdding: .month, value: -12, to: season.start) ?? season.start
                return DateInterval(start: start, end: season.start)
            }
        }
    }

    /// The season `date` falls in: from the 1st of the most recent
    /// `startMonth` on or before it, for twelve months. Nil when no month is
    /// set (outside 1–12). Months are counted in the Gregorian calendar, as
    /// Season Starts stores them, in `calendar`'s time zone.
    static func season(containing date: Date, startMonth: Int, calendar: Calendar = .current) -> DateInterval? {
        guard (1...12).contains(startMonth) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return nil }
        let startYear = month >= startMonth ? year : year - 1
        guard let start = gregorian.date(from: DateComponents(year: startYear, month: startMonth, day: 1)),
              let end = gregorian.date(byAdding: .month, value: 12, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// A category's spending in the period.
    struct CategoryTotal: Equatable {
        let category: ExpenseCategory
        let amount: Double
    }

    struct Figures: Equatable {
        /// Categories with spending in the period, in the editor's order.
        let byCategory: [CategoryTotal]
        /// Everything spent in the period (`Expenses.total`).
        let spent: Double
        /// The trips' distance in the unit asked for (`Mileage.total`).
        let distance: Double
        /// Money received in the period (`Payments.received(_:in:)`).
        let income: Double
        /// Income less spent, to the cent: below zero for a loss.
        let net: Double
    }

    /// The figures for `period` (start included, end not), for
    /// `operatorID`'s expenses, trips and invoices only.
    static func figures(expenses: [Expense], mileage: [MileageEntry], documents: [Proposal],
                        operatorID: String, period: DateInterval, unit: DistanceUnit) -> Figures {
        func inPeriod(_ date: Date) -> Bool { date >= period.start && date < period.end }
        let spending = expenses.filter { $0.operatorID == operatorID && inPeriod($0.date) }
        let trips = mileage.filter { $0.operatorID == operatorID && inPeriod($0.date) }
        let invoices = documents.filter { $0.operatorID == operatorID }

        let byCategory = ExpenseCategory.allCases.compactMap { category -> CategoryTotal? in
            let theirs = spending.filter { $0.category == category }
            return theirs.isEmpty ? nil : CategoryTotal(category: category, amount: Expenses.total(theirs))
        }
        let spent = Expenses.total(spending)
        let income = Payments.received(invoices, in: period)
        return Figures(byCategory: byCategory, spent: spent, distance: Mileage.total(trips, in: unit),
                       income: income, net: InvoiceLines.roundedToCent(income - spent))
    }
}
