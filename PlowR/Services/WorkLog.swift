import Foundation
import SwiftData

/// The Work Log: every job in the Service Log across all clients, for a
/// period, grouped by day, filtered and added up. It reads `ServiceRecord`
/// only: completed visits already have one (`ServiceLog.backfillCompletedVisits`).
/// It lists every record, as Service History and the Season Report do;
/// copies are `ServiceLog.mergeDuplicates`'s job, not this one's.
enum WorkLog {
    /// The days shown. Each runs from its start, up to but not including its
    /// end, as `SeasonReport.Period` and `WorkBilling.Period` do.
    enum Period: String, CaseIterable, Identifiable {
        case today, yesterday, thisWeek, lastWeek, thisMonth, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .thisWeek: "This Week"
            case .lastWeek: "Last Week"
            case .thisMonth: "This Month"
            case .custom: "Custom Dates"
            }
        }

        /// The dates covered. Weeks follow the calendar's first weekday.
        /// Custom runs from the start of its first day up to the start of the
        /// day after its last (a last day before the first counts as the
        /// first); with no custom dates it's today.
        func interval(now: Date, calendar: Calendar = .current,
                      custom: (start: Date, end: Date)? = nil) -> DateInterval {
            let today = Self.day(of: now, calendar: calendar)
            switch self {
            case .today:
                return today
            case .yesterday:
                let start = calendar.date(byAdding: .day, value: -1, to: today.start) ?? today.start
                return Self.day(of: start, calendar: calendar)
            case .thisWeek:
                return calendar.dateInterval(of: .weekOfYear, for: now) ?? today
            case .lastWeek:
                let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) ?? today
                let inLastWeek = calendar.date(byAdding: .day, value: -1, to: thisWeek.start) ?? thisWeek.start
                return calendar.dateInterval(of: .weekOfYear, for: inLastWeek) ?? thisWeek
            case .thisMonth:
                guard let range = WorkBilling.Period.thisMonth.range(now: now, calendar: calendar) else { return today }
                return DateInterval(start: range.lowerBound, end: range.upperBound)
            case .custom:
                guard let custom else { return today }
                let first = Self.day(of: custom.start, calendar: calendar)
                let last = Self.day(of: max(custom.start, custom.end), calendar: calendar)
                return DateInterval(start: first.start, end: last.end)
            }
        }

        private static func day(of date: Date, calendar: Calendar) -> DateInterval {
            calendar.dateInterval(of: .day, for: date)
                ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        }
    }

    /// Which jobs by where they stand with billing (`ServiceLog.billingStatus`).
    /// Covered, no charge and not tracked show only under All.
    enum BillingFilter: String, CaseIterable, Identifiable {
        case all, notBilled, invoiced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .notBilled: "Not Billed"
            case .invoiced: "Invoiced"
            }
        }

        func includes(_ status: ServiceLog.BillingStatus) -> Bool {
            switch self {
            case .all: true
            case .notBilled: status == .notBilled
            case .invoiced: status == .invoiced
            }
        }
    }

    /// A service done: a line's `serviceID`, or its name when it has none
    /// (a custom line).
    nonisolated struct ServiceKey: Hashable, Identifiable {
        let raw: String
        var id: String { raw }

        init(_ line: ServiceRecord.Line) {
            raw = line.serviceID.isEmpty ? "name:\(line.name)" : "id:\(line.serviceID)"
        }
    }

    /// A service the records used, as the filter offers it.
    nonisolated struct ServiceOption: Identifiable, Equatable {
        let key: ServiceKey
        let name: String
        var id: ServiceKey { key }
    }

    /// The distinct services done in `records`, each named by its most
    /// recent line, sorted by name: what was actually done, including
    /// services since deleted from the catalog.
    static func services(in records: [ServiceRecord]) -> [ServiceOption] {
        var latest: [ServiceKey: (name: String, at: Date)] = [:]
        for record in records {
            for line in record.lines {
                let key = ServiceKey(line)
                if let seen = latest[key], seen.at >= record.performedAt { continue }
                latest[key] = (line.name, record.performedAt)
            }
        }
        return latest.map { ServiceOption(key: $0.key, name: $0.value.name) }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.key.raw < $1.key.raw : order == .orderedAscending
            }
    }

    /// A job's recorded value: with no service chosen, exactly
    /// `ServiceLog.total(of:)`; with one, only that service's lines. At the
    /// prices recorded, before discounts, tax and contracts. Rows and totals
    /// both use this.
    static func value(of record: ServiceRecord, service: ServiceKey?) -> Double {
        guard let service else { return ServiceLog.total(of: record) }
        return InvoiceLines.roundedToCent(
            record.lines.filter { ServiceKey($0) == service }.reduce(0) { $0 + $1.price })
    }

    /// Where a job stands with billing, from invoices and contracts looked
    /// up once for the list, as Service History works it out.
    static func status(of record: ServiceRecord, invoiceIDs: Set<String>,
                       contracts: [Contract]) -> ServiceLog.BillingStatus {
        ServiceLog.billingStatus(of: record, invoiced: invoiceIDs.contains(record.invoiceID),
                                 covered: ServiceLog.isCovered(record, contracts: contracts))
    }

    /// A filtered list added up.
    struct Totals: Equatable {
        let count: Int
        /// `record.minutes` added up, as the Season Report adds them.
        let minutes: Double
        let value: Double

        init(count: Int, minutes: Double, value: Double) {
            self.count = count
            self.minutes = minutes
            self.value = value
        }

        init(_ records: [ServiceRecord], service: ServiceKey?) {
            count = records.count
            minutes = records.reduce(0) { $0 + $1.minutes }
            value = InvoiceLines.roundedToCent(records.reduce(0) { $0 + WorkLog.value(of: $1, service: service) })
        }
    }

    /// Records by day (`startOfDay(performedAt)`), days newest first and
    /// records newest first within a day.
    static func days(_ records: [ServiceRecord], calendar: Calendar = .current)
        -> [(day: Date, records: [ServiceRecord])] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.performedAt) }
            .map { (day: $0.key, records: $0.value.sorted { $0.performedAt > $1.performedAt }) }
            .sorted { $0.day > $1.day }
    }

    /// The business's records with the chosen service and billing status.
    /// `invoiceIDs` (`ServiceLog.invoiceIDs(in:)`) and `contracts`
    /// (`Contracts.all(in:)`) are looked up once by the caller.
    static func filter(_ records: [ServiceRecord], operatorID: String, service: ServiceKey?,
                       billing: BillingFilter, invoiceIDs: Set<String>,
                       contracts: [Contract]) -> [ServiceRecord] {
        records.filter { record in
            guard record.operatorID == operatorID else { return false }
            if let service, !record.lines.contains(where: { ServiceKey($0) == service }) { return false }
            guard billing != .all else { return true }
            return billing.includes(status(of: record, invoiceIDs: invoiceIDs, contracts: contracts))
        }
    }
}
