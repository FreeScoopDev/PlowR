import Foundation

/// The Season Report's figures for a chosen period. It covered all time
/// whatever the season, and rounded money to whole dollars (pre-launch
/// review, 2026-10-10): visits and minutes now come from the Service Log's
/// records in the period, money received from payments that came in it, and
/// money owed is what's owed now. Kept apart from the drawing so it's tested.
enum SeasonReport {
    enum Period: String, CaseIterable, Identifiable {
        case thisYear, last12Months, lastYear, allTime

        var id: String { rawValue }

        var title: String {
            switch self {
            case .thisYear: "This Year"
            case .last12Months: "Last 12 Months"
            case .lastYear: "Last Year"
            case .allTime: "All Time"
            }
        }

        /// The dates covered: from the start, up to but not including the
        /// end (so midnight on January 1 is this year's, not last year's).
        /// Periods running to today end just after `now`.
        func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
            let year = calendar.dateInterval(of: .year, for: now)
            let throughNow = now.addingTimeInterval(1)
            switch self {
            case .thisYear:
                return DateInterval(start: year?.start ?? now, end: throughNow)
            case .last12Months:
                // From the start of that day, as the title names it.
                let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
                return DateInterval(start: calendar.startOfDay(for: start), end: throughNow)
            case .lastYear:
                let start = calendar.date(byAdding: .year, value: -1, to: year?.start ?? now) ?? now
                return DateInterval(start: start, end: year?.start ?? now)
            case .allTime:
                return DateInterval(start: .distantPast, end: throughNow)
            }
        }
    }

    struct ClientRow: Equatable {
        let name: String
        let visits: Int
        let collected: Double
        let lastService: Date?
    }

    struct Month: Equatable {
        let start: Date
        let received: Double
    }

    struct Figures {
        let period: DateInterval
        let clientCount: Int
        let visits: Int
        let minutes: Double
        let collected: Double
        /// What's owed today, whatever the period (Payments.owed).
        let owedNow: Double
        /// Money received in each month of the period with any, newest first.
        let months: [Month]
        /// Clients with a visit or a payment in the period, the most visits first.
        let clients: [ClientRow]
    }

    /// The figures for `period`. Rows are by client ID, so a client since
    /// removed (their records and invoices kept) is listed by the name kept
    /// with them, and the rows add up to the totals.
    static func figures(clients: [Client], proposals: [Proposal], records: [ServiceRecord],
                        period: DateInterval, calendar: Calendar = .current) -> Figures {
        func inPeriod(_ date: Date) -> Bool { date >= period.start && date < period.end }
        let visits = records.filter { inPeriod($0.performedAt) }
        let invoices = proposals.filter(\.isInvoice)
        let names = Dictionary(clients.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })

        let visitsByClient = Dictionary(grouping: visits, by: \.clientID)
        let invoicesByClient = Dictionary(grouping: invoices, by: \.clientID)
        let rows = Set(visitsByClient.keys).union(invoicesByClient.keys).compactMap { id -> ClientRow? in
            let theirs = visitsByClient[id] ?? []
            let collected = Payments.received(invoicesByClient[id] ?? [], in: period)
            guard !theirs.isEmpty || collected > 0 else { return nil }
            let name = names[id] ?? theirs.first?.clientName ?? invoicesByClient[id]?.first?.clientName ?? "Client"
            return ClientRow(name: name.isEmpty ? "Client" : name, visits: theirs.count, collected: collected,
                             lastService: theirs.map(\.performedAt).max())
        }
        .sorted { a, b in
            (a.visits, a.collected) != (b.visits, b.collected)
                ? (a.visits, a.collected) > (b.visits, b.collected)
                : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return Figures(period: period, clientCount: rows.count, visits: visits.count,
                       minutes: visits.reduce(0) { $0 + $1.minutes },
                       collected: Payments.received(invoices, in: period), owedNow: Payments.owed(invoices),
                       months: Payments.receivedByMonth(invoices, in: period, calendar: calendar)
                           .map { Month(start: $0.start, received: $0.amount) },
                       clients: rows)
    }

    /// Money as the report prints it: to the cent, with thousands separators.
    static func money(_ amount: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        amount.formatted(.currency(code: "USD").locale(locale))
    }
}
