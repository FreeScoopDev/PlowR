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

        /// The dates covered, up to `now`.
        func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
            let year = calendar.dateInterval(of: .year, for: now)
            switch self {
            case .thisYear:
                return DateInterval(start: year?.start ?? now, end: now)
            case .last12Months:
                return DateInterval(start: calendar.date(byAdding: .month, value: -12, to: now) ?? now, end: now)
            case .lastYear:
                let start = calendar.date(byAdding: .year, value: -1, to: year?.start ?? now) ?? now
                return DateInterval(start: start, end: year?.start ?? now)
            case .allTime:
                return DateInterval(start: .distantPast, end: now)
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

    static func figures(clients: [Client], proposals: [Proposal], records: [ServiceRecord],
                        period: DateInterval, calendar: Calendar = .current) -> Figures {
        func inPeriod(_ date: Date) -> Bool { date >= period.start && date <= period.end }
        let visits = records.filter { inPeriod($0.performedAt) }
        let invoices = proposals.filter(\.isInvoice)

        func received(_ documents: [Proposal]) -> [(date: Date, amount: Double)] {
            Payments.receipts(documents).filter { inPeriod($0.date) }
        }
        func total(_ receipts: [(date: Date, amount: Double)]) -> Double {
            InvoiceLines.roundedToCent(receipts.reduce(0) { $0 + $1.amount })
        }

        var byMonth: [Date: Double] = [:]
        for receipt in received(invoices) {
            let month = calendar.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
            byMonth[month, default: 0] += receipt.amount
        }
        let months = byMonth.map { Month(start: $0.key, received: InvoiceLines.roundedToCent($0.value)) }
            .sorted { $0.start > $1.start }

        let rows = clients.compactMap { client -> ClientRow? in
            let id = client.id.uuidString
            let theirs = visits.filter { $0.clientID == id }
            let collected = total(received(invoices.filter { $0.clientID == id }))
            guard !theirs.isEmpty || collected > 0 else { return nil }
            return ClientRow(name: client.name, visits: theirs.count, collected: collected,
                             lastService: theirs.map(\.performedAt).max())
        }
        .sorted { ($0.visits, $0.collected) > ($1.visits, $1.collected) }

        return Figures(period: period, clientCount: rows.count, visits: visits.count,
                       minutes: visits.reduce(0) { $0 + $1.minutes },
                       collected: total(received(invoices)), owedNow: Payments.owed(invoices),
                       months: months, clients: rows)
    }

    /// Money as the report prints it: to the cent, with thousands separators.
    static func money(_ amount: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        amount.formatted(.currency(code: "USD").locale(locale))
    }
}
