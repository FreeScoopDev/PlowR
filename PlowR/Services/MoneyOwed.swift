import Foundation

/// Money owed, by how late it is: what's not due yet, and what's 1–30,
/// 31–60, 61–90 and over 90 days past its due date, in all and client by
/// client. Each invoice's balance (Proposal.balanceDue) is what's owed, so
/// the total is the one on the Dashboard.
enum MoneyOwed {
    enum Age: Int, CaseIterable, Identifiable, Comparable {
        case notDue, upTo30, upTo60, upTo90, over90

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .notDue: "Not Due Yet"
            case .upTo30: "1–30 Days Late"
            case .upTo60: "31–60 Days Late"
            case .upTo90: "61–90 Days Late"
            case .over90: "Over 90 Days Late"
            }
        }

        static func < (lhs: Age, rhs: Age) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How late `invoice` is. Late means overdue as its status says it (sent,
    /// past its due date), counted in whole days, at least one. A draft, or
    /// one with no due date, isn't late.
    static func age(of invoice: Proposal, now: Date, calendar: Calendar = .current) -> Age {
        guard invoice.invoiceSentAt != nil, let due = invoice.invoiceDueDate, due < now else { return .notDue }
        let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: due),
                                                  to: calendar.startOfDay(for: now)).day ?? 1)
        switch days {
        case ...30: return .upTo30
        case ...60: return .upTo60
        case ...90: return .upTo90
        default: return .over90
        }
    }

    /// One client's money owed.
    struct ClientOwed: Identifiable {
        let clientID: String
        let name: String
        /// Their invoices with a balance, most overdue first.
        let invoices: [Proposal]
        let owed: Double
        /// How late the latest of their invoices is.
        let oldest: Age
        var id: String { clientID }
    }

    struct Summary {
        /// What's owed at each age; every age is there, zero or not.
        let byAge: [Age: Double]
        /// Clients who owe, the latest payers first, then the most owed.
        let clients: [ClientOwed]
        var total: Double { InvoiceLines.roundedToCent(byAge.values.reduce(0, +)) }
    }

    static func summary(_ documents: [Proposal], operatorID: String, now: Date = .now,
                        calendar: Calendar = .current) -> Summary {
        let owing = documents.filter { $0.operatorID == operatorID && Payments.isOwed($0) }
        var byAge = Dictionary(uniqueKeysWithValues: Age.allCases.map { ($0, 0.0) })
        for invoice in owing { byAge[age(of: invoice, now: now, calendar: calendar), default: 0] += invoice.balanceDue }
        byAge = byAge.mapValues { InvoiceLines.roundedToCent($0) }

        let clients = Dictionary(grouping: owing, by: \.clientID).map { clientID, invoices -> ClientOwed in
            let sorted = invoices.sorted {
                ($0.invoiceDueDate ?? .distantFuture, $0.createdAt) < ($1.invoiceDueDate ?? .distantFuture, $1.createdAt)
            }
            let name = sorted.map { $0.clientName }.first { !$0.isEmpty } ?? "Client"
            return ClientOwed(clientID: clientID, name: name, invoices: sorted,
                              owed: Payments.owed(sorted),
                              oldest: sorted.map { age(of: $0, now: now, calendar: calendar) }.max() ?? .notDue)
        }
        .sorted { ($0.oldest, $0.owed) > ($1.oldest, $1.owed) }
        return Summary(byAge: byAge, clients: clients)
    }
}
