import Foundation
import SwiftData

/// Billing work in bulk: for a period, each client's jobs in the Service Log
/// that aren't billed yet, and one draft invoice per client for them, a line
/// per service done with the day and the address under it. This is how
/// seasonal and weekly work is usually billed: once a month, not a job at a
/// time.
enum WorkBilling {
    /// The period to bill.
    enum Period: String, CaseIterable, Identifiable {
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case everything = "All Unbilled"

        var id: String { rawValue }

        /// Its start and end (end excluded), or nil for all work up to now.
        func range(now: Date, calendar: Calendar = .current) -> Range<Date>? {
            guard self != .everything,
                  let thisMonth = calendar.dateInterval(of: .month, for: now) else { return nil }
            if self == .thisMonth { return thisMonth.start..<thisMonth.end }
            guard let start = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) else { return nil }
            return start..<thisMonth.start
        }
    }

    /// A client's work to bill.
    struct ClientWork: Identifiable {
        let client: Client
        /// One per job, oldest first, as the invoice lists them.
        let records: [ServiceRecord]
        /// What each job charges (ServiceLog.charge): under a per-visit
        /// contract, its price; services a contract covers, nothing.
        var charges: [UUID: [ServiceRecord.Line]] = [:]
        var id: UUID { client.id }
        /// Jobs with a service priced by the square foot at $0: done at a
        /// place with no measured area, recorded from a route or the
        /// Schedule without a price (InvoiceLines.needsPrice). Pointed out,
        /// so a $0 line doesn't go on an invoice unseen.
        var jobsNeedingAPrice: Int {
            records.filter { record in
                (charges[record.id] ?? record.lines).contains { $0.unitType == "perSqFt" && $0.price <= 0 }
            }.count
        }
        var total: Double {
            InvoiceLines.roundedToCent(records.reduce(0) { sum, record in
                sum + (charges[record.id] ?? record.lines).reduce(0) { $0 + $1.price }
            })
        }
    }

    /// Each of this operator's clients with work not billed yet in `range`,
    /// by client name. Not billed yet is ServiceLog's rule (billable, not on
    /// an invoice, not from before the log). A job with no services has
    /// nothing to bill, and work whose client is gone has no one to bill.
    ///
    /// The same job recorded on two devices before they synced (one source
    /// key, two records, until ServiceLog.mergeDuplicates merges them a day
    /// later) is one job: the oldest record stands for it, and if any copy is
    /// already on an invoice the job is left out, so it's never billed twice.
    /// If the copies' services differ (the office ticked the visit off with
    /// its usual services, the crew recorded what was done), the job waits
    /// for the merge, which keeps the recorded ones: billing either copy now
    /// could bill the wrong services.
    static func unbilledWork(in range: Range<Date>?, operatorID: String, clientID: String? = nil,
                             in context: ModelContext) -> [ClientWork] {
        guard let all = try? context.fetch(FetchDescriptor<ServiceRecord>()),
              let clients = try? context.fetch(FetchDescriptor<Client>()) else { return [] }
        let invoiceIDs = ServiceLog.invoiceIDs(in: context)
        let contracts = Contracts.all(in: context)
        let byID = Dictionary(clients.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let mine = all.filter { $0.operatorID == operatorID && (clientID == nil || $0.clientID == clientID) }
        let jobs = oneRecordPerJob(mine, invoiceIDs: invoiceIDs)
        // Cheapest checks first: decoding a record's services comes last. A
        // job a contract covers entirely charges nothing, and isn't billed.
        var charges: [UUID: [ServiceRecord.Line]] = [:]
        let toBill = jobs.filter { record in
            guard range?.contains(record.performedAt) ?? true else { return false }
            let charge = ServiceLog.charge(of: record, contracts: contracts)
            charges[record.id] = charge
            let covered = !record.lines.isEmpty && charge.isEmpty
            return ServiceLog.billingStatus(of: record, invoiced: invoiceIDs.contains(record.invoiceID),
                                            covered: covered) == .notBilled && !charge.isEmpty
        }
        return Dictionary(grouping: toBill, by: \.clientID)
            .compactMap { clientID, records in
                byID[clientID].map {
                    ClientWork(client: $0, records: records.sorted { $0.performedAt < $1.performedAt },
                               charges: charges.filter { id, _ in records.contains { $0.id == id } })
                }
            }
            .sorted { $0.client.name.localizedCaseInsensitiveCompare($1.client.name) == .orderedAscending }
    }

    /// One record per job: copies sharing a source key are one job, stood
    /// for by the oldest. None of it if any copy is already invoiced, or if
    /// the copies' services differ (waiting for the merge).
    private static func oneRecordPerJob(_ records: [ServiceRecord], invoiceIDs: Set<String>) -> [ServiceRecord] {
        Dictionary(grouping: records) { $0.sourceKey.isEmpty ? $0.id.uuidString : $0.sourceKey }
            .values
            .compactMap { copies in
                if copies.contains(where: { invoiceIDs.contains($0.invoiceID) }) { return nil }
                // Compared as services, not as the saved JSON, whose key order varies.
                if let first = copies.first?.lines, copies.contains(where: { $0.lines != first }) { return nil }
                return ServiceLog.oldest(copies)
            }
    }

    /// A draft invoice for `work` (ServiceLog.newDraftInvoice): a line per
    /// service done, oldest job first, each with its day (and the address,
    /// when it isn't the client's) under it. Checked again now: a job billed
    /// since the list was made (on this screen, from Record Services, from
    /// another device) is left off, and with none left there's no invoice.
    /// Every copy of each job is billed on it, and a scheduled visit among
    /// them is linked to it, so the Schedule doesn't offer to invoice it again.
    @discardableResult
    static func invoice(_ work: ClientWork, operatorID: String, now: Date = .now, calendar: Calendar = .current,
                        in context: ModelContext) -> Proposal? {
        let invoiceIDs = ServiceLog.invoiceIDs(in: context)
        let all = (try? context.fetch(FetchDescriptor<ServiceRecord>())) ?? []
        // The records as they are now: one deleted since (here or on another
        // device) isn't among them, and isn't billed.
        let live = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let copiesByKey = Dictionary(grouping: all.filter { !$0.sourceKey.isEmpty }, by: \.sourceKey)
        func copies(of record: ServiceRecord) -> [ServiceRecord] {
            record.sourceKey.isEmpty ? [record] : copiesByKey[record.sourceKey] ?? [record]
        }
        // What each charges now: a contract signed or cancelled since counts.
        let contracts = Contracts.all(in: context)
        let charges = Dictionary(uniqueKeysWithValues: work.records.compactMap { live[$0.id] }.map {
            ($0.id, ServiceLog.charge(of: $0, contracts: contracts))
        })
        let jobs = work.records.compactMap { live[$0.id] }.filter { record in
            // A contract signed since the list was made counts: covered now, left off.
            ServiceLog.billingStatus(of: record, invoiced: false,
                                     covered: !record.lines.isEmpty && (charges[record.id] ?? []).isEmpty) == .notBilled
                && !(charges[record.id] ?? []).isEmpty
                && !copies(of: record).contains { invoiceIDs.contains($0.invoiceID) }
        }
        guard !jobs.isEmpty else { return nil }

        var items: [ProposalLineItem] = []
        for record in jobs {
            var note = day(record.performedAt, now: now, calendar: calendar)
            if !record.propertyAddress.isEmpty, record.propertyAddress != work.client.address {
                note += " · \(record.propertyAddress)"
            }
            for line in charges[record.id] ?? record.lines {
                let item = ProposalLineItem(serviceName: line.name, zoneLabel: "", quantity: 1, unitType: "flat",
                                            unitPrice: line.price, sortOrder: items.count, itemNotes: note)
                item.lineTotal = line.price
                items.append(item)
            }
        }
        let proposal = ServiceLog.newDraftInvoice(for: work.client, items: items, operatorID: operatorID,
                                                  now: now, in: context)
        let visits = (try? context.fetch(FetchDescriptor<ScheduledVisit>())) ?? []
        for record in jobs {
            for copy in copies(of: record) { copy.invoiceID = proposal.id.uuidString }
            if let visit = visits.first(where: { $0.id.uuidString == record.visitID }) {
                ServiceLog.link(visit, to: proposal, in: context)
            }
        }
        return proposal
    }

    /// "Sep 12", with the year when it isn't this year's: an invoice sent to
    /// a client can cover more than twelve months.
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// What billing several clients made: the invoices, and whether it
    /// stopped short because one couldn't be saved.
    struct Outcome {
        var invoices: [Proposal] = []
        var stoppedShort = false
    }

    /// Draft invoices for each of `works`, each saved as it's made. If one
    /// can't be saved it's undone and billing stops there; the ones before it
    /// stay made. Each takes the next invoice number. (Undoing rolls back the
    /// whole context: anything else unsaved in it goes too. Autosave leaves
    /// little pending, and a save that fails usually fails on that.)
    static func invoiceAll(_ works: [ClientWork], operatorID: String, now: Date = .now,
                           in context: ModelContext) -> Outcome {
        var outcome = Outcome()
        for work in works {
            guard let proposal = invoice(work, operatorID: operatorID, now: now, in: context) else { continue }
            do {
                try context.save()
                outcome.invoices.append(proposal)
            } catch {
                context.rollback()
                outcome.stoppedShort = true
                break
            }
        }
        return outcome
    }
}
