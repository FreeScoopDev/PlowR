import Foundation
import SwiftData

/// Writes the Service Log (ServiceRecord): one record each time work is done
/// at a property, when a route stop is completed or a scheduled visit is
/// marked complete.
///
/// Each record has a source key, so writing the same work again (the stop
/// completed after its services were recorded, say) updates that record
/// instead of adding a second one.
///
/// A route stop and a scheduled visit can be the same work: routes are built
/// from the day's visits, and running one used to leave the visit "due", to
/// be ticked off again later. Completing a stop now completes the client's
/// visit for that day when there's exactly one (Joe's call), and both write
/// the one record, under the visit's key.
enum ServiceLog {
    static func stopKey(run: UUID, stop: UUID) -> String { "stop:\(run.uuidString):\(stop.uuidString)" }
    static func visitKey(_ visitID: UUID) -> String { "visit:\(visitID.uuidString)" }

    /// The record with this source key, if there is one. The oldest, if two
    /// devices each made one: every device then updates the same one.
    static func record(forKey key: String, in context: ModelContext) -> ServiceRecord? {
        let descriptor = FetchDescriptor<ServiceRecord>(
            predicate: #Predicate { $0.sourceKey == key },
            sortBy: [SortDescriptor(\.createdAt)])
        return try? context.fetch(descriptor).first
    }

    /// A client's records, newest first.
    static func records(ofClient clientID: String, in context: ModelContext) -> [ServiceRecord] {
        let descriptor = FetchDescriptor<ServiceRecord>(
            predicate: #Predicate { $0.clientID == clientID },
            sortBy: [SortDescriptor(\.performedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The record for `key`, made (for `client`) if there isn't one yet, and
    /// whether it was just made. A new record is billable unless the client
    /// is comped: that is decided when the work is done, not changed later.
    private static func record(forKey key: String, source: ServiceRecordSource, operatorID: String,
                               client: Client, in context: ModelContext) -> (record: ServiceRecord, isNew: Bool) {
        if let existing = record(forKey: key, in: context) { return (existing, false) }
        let record = ServiceRecord(operatorID: operatorID, sourceKey: key, source: source)
        record.clientID = client.id.uuidString
        // A client's main property will have the client's ID (Properties).
        record.propertyID = client.id.uuidString
        record.isBillable = !client.isComped
        context.insert(record)
        return (record, true)
    }

    // MARK: - A route stop

    /// Records the work at `stop` on route run `run`: its times, and the
    /// services recorded on it so far. Called when the stop is completed.
    /// If the client has exactly one visit the day the stop was started,
    /// it's completed too and shares the record (`visitForStop`).
    @discardableResult
    static func recordStop(_ stop: RouteStop, of client: Client, run: UUID, operatorID: String,
                           startedAt: Date, finishedAt: Date, minutes: Double, in context: ModelContext,
                           calendar: Calendar = .current) -> ServiceRecord {
        let (record, visit) = recordForStop(stop, of: client, run: run, operatorID: operatorID,
                                            startedAt: startedAt, in: context, calendar: calendar)
        if let visit, visit.status == .scheduled { markCompleted(visit, at: finishedAt, in: context) }
        record.startedAt = startedAt
        record.performedAt = finishedAt
        record.minutes = max(0, minutes)
        // Record Services' own lines (typed prices, custom items) stand; the
        // catalog prices only fill a record that has none.
        if record.lines.isEmpty, !stop.completedServiceIDs.isEmpty {
            record.lines = lines(for: stop.completedServiceIDs, client: client, in: context)
        }
        if record.notes.isEmpty, !stop.completedNotes.isEmpty { record.notes = stop.completedNotes }
        return record
    }

    /// The record for the work at `stop` on run `run`, made if there's none
    /// yet, with who, where and which route filled in, and the day's visit it
    /// shares, if any (not completed here). Record Services writes to it
    /// before the stop is completed and completing adds the times, so both
    /// must find the same one: first by run and stop, which doesn't change
    /// at midnight; failing that by the day the stop was started (`startedAt`),
    /// never the time of saving, which can be past midnight on a night route.
    static func recordForStop(_ stop: RouteStop, of client: Client, run: UUID, operatorID: String,
                              startedAt: Date, in context: ModelContext,
                              calendar: Calendar = .current) -> (record: ServiceRecord, visit: ScheduledVisit?) {
        let found = lookup(stop, of: client, run: run, startedAt: startedAt, in: context, calendar: calendar)
        let visit = found.visit
        let made = Self.record(forKey: found.key, source: .route, operatorID: operatorID, client: client, in: context)
        let record = made.record
        // A record completed from the Schedule keeps its date until the
        // stop's times arrive.
        if made.isNew { record.performedAt = startedAt }
        if let visit {
            record.visitID = visit.id.uuidString
            record.source = .route
            billFromVisit(record, visit, in: context)
        }
        record.clientName = client.name
        record.propertyAddress = stop.clientAddress
        record.routeID = stop.route?.id.uuidString ?? ""
        record.routeName = stop.route?.name ?? ""
        record.runID = run.uuidString
        record.stopID = stop.id.uuidString
        return (record, visit)
    }

    /// The record `recordForStop` would use, if it exists yet; nothing is made.
    static func existingRecordForStop(_ stop: RouteStop, of client: Client, run: UUID, startedAt: Date,
                                      in context: ModelContext, calendar: Calendar = .current) -> ServiceRecord? {
        let found = lookup(stop, of: client, run: run, startedAt: startedAt, in: context, calendar: calendar)
        return record(forKey: found.key, in: context)
    }

    /// The invoice the work at `stop` is already on: its record's, or, before
    /// there's a record, the one made for the day's visit it will share.
    static func invoiceForStop(_ stop: RouteStop, of client: Client, run: UUID, startedAt: Date,
                               in context: ModelContext, calendar: Calendar = .current) -> Proposal? {
        let found = lookup(stop, of: client, run: run, startedAt: startedAt, in: context, calendar: calendar)
        if let record = record(forKey: found.key, in: context), let invoice = invoice(of: record, in: context) {
            return invoice
        }
        return found.visit.flatMap { invoice(ofVisit: $0, in: context) }
    }

    /// The one rule for which record a stop's work is: the one this run
    /// already has for the stop, or else the day's visit's, or the stop's own.
    private static func lookup(_ stop: RouteStop, of client: Client, run: UUID, startedAt: Date,
                               in context: ModelContext, calendar: Calendar) -> (key: String, visit: ScheduledVisit?) {
        if let existing = runRecord(for: stop, run: run, in: context) {
            return (existing.sourceKey, scheduledVisit(existing.visitID, in: context))
        }
        let visit = visitForStop(stop, of: client, run: run, on: startedAt, in: context, calendar: calendar)
        return (visit.map { visitKey($0.id) } ?? stopKey(run: run, stop: stop.id), visit)
    }

    /// The record this run already has for `stop` (the oldest, as `record(forKey:)`).
    private static func runRecord(for stop: RouteStop, run: UUID, in context: ModelContext) -> ServiceRecord? {
        let runID = run.uuidString
        let stopID = stop.id.uuidString
        let descriptor = FetchDescriptor<ServiceRecord>(
            predicate: #Predicate { $0.runID == runID && $0.stopID == stopID },
            sortBy: [SortDescriptor(\.createdAt)])
        return try? context.fetch(descriptor).first
    }

    private static func scheduledVisit(_ id: String, in context: ModelContext) -> ScheduledVisit? {
        guard !id.isEmpty else { return nil }
        // Matched by string: a #Predicate on `id` clashes with SwiftData's own id.
        return try? context.fetch(FetchDescriptor<ScheduledVisit>()).first { $0.id.uuidString == id }
    }

    /// The client's visit that `stop`, started on `day` by run `run`, is:
    /// their only visit that day that's scheduled or done. None when there
    /// are two or more (which one was it?), or when that visit's work is
    /// already another stop's: done by another run (a second pass is its own
    /// work), or another stop for the client on this run. A visit another
    /// run recorded but never completed is taken over by this one, so the
    /// visit gets completed.
    static func visitForStop(_ stop: RouteStop, of client: Client, run: UUID, on day: Date,
                             in context: ModelContext, calendar: Calendar = .current) -> ScheduledVisit? {
        let clientID = client.id.uuidString
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let descriptor = FetchDescriptor<ScheduledVisit>(predicate: #Predicate {
            $0.clientID == clientID && $0.scheduledDate >= start && $0.scheduledDate < end
        })
        let sameDay = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.status == .scheduled || $0.status == .completed }
        guard sameDay.count == 1, let visit = sameDay.first else { return nil }
        guard let claimed = record(forKey: visitKey(visit.id), in: context) else { return visit }
        // Done from the Schedule (no run yet).
        if claimed.runID.isEmpty { return visit }
        if claimed.runID == run.uuidString { return claimed.stopID == stop.id.uuidString ? visit : nil }
        return visit.status == .scheduled ? visit : nil
    }

    // MARK: - Invoices

    /// The invoice `record` is billed on, if it still exists. An ID left by an
    /// invoice deleted some other way (another device, an older PlowR) is
    /// treated as unbilled.
    static func invoice(of record: ServiceRecord, in context: ModelContext) -> Proposal? {
        document(record.invoiceID, in: context).flatMap { $0.isInvoice ? $0 : nil }
    }

    /// Whether `record`'s services are fixed: it's on an invoice and has
    /// services, so it matches that bill. Change the invoice instead.
    static func servicesLocked(_ record: ServiceRecord, in context: ModelContext) -> Bool {
        !record.lines.isEmpty && invoice(of: record, in: context) != nil
    }

    /// Work that goes on a bill and isn't on one yet. The one definition:
    /// an invoice that no longer exists doesn't count.
    static func isUnbilled(_ record: ServiceRecord, in context: ModelContext) -> Bool {
        record.isBillable && invoice(of: record, in: context) == nil
    }

    /// The invoice made for `visit` (Schedule → Invoice), if it exists and
    /// is an invoice, not a proposal.
    static func invoice(ofVisit visit: ScheduledVisit, in context: ModelContext) -> Proposal? {
        document(visit.proposalID, in: context).flatMap { $0.isInvoice ? $0 : nil }
    }

    private static func document(_ id: String, in context: ModelContext) -> Proposal? {
        guard !id.isEmpty else { return nil }
        return try? context.fetch(FetchDescriptor<Proposal>()).first { $0.id.uuidString == id }
    }

    /// A record for `visit` is billed on the invoice already made for the
    /// visit (Schedule → Invoice can come before the work is done).
    private static func billFromVisit(_ record: ServiceRecord, _ visit: ScheduledVisit, in context: ModelContext) {
        guard invoice(of: record, in: context) == nil, let invoice = invoice(ofVisit: visit, in: context) else { return }
        record.invoiceID = invoice.id.uuidString
    }

    // MARK: - Record Services

    /// Saves what Record Services has for `stop` into its record (the same
    /// one completing the stop fills in): the services at the prices on
    /// screen, custom items, notes. The stop keeps the service IDs too, for
    /// the route screen's "N recorded". A record already on an invoice keeps
    /// its services, so it still matches the bill; notes still change. (One
    /// with no services yet, billed on an invoice made for its visit before
    /// the work, takes them: it matches no bill without them.)
    @discardableResult
    static func saveRecording(_ recording: StopRecording, notes: String, for stop: RouteStop, of client: Client,
                              run: UUID, operatorID: String, startedAt: Date,
                              in context: ModelContext) -> ServiceRecord {
        let (record, _) = recordForStop(stop, of: client, run: run, operatorID: operatorID,
                                        startedAt: startedAt, in: context)
        stop.completedNotes = notes
        record.notes = notes
        if servicesLocked(record, in: context) { return record }
        if invoice(of: record, in: context) == nil { record.invoiceID = "" }
        record.lines = recording.recordLines
        stop.completedServiceIDs = recording.services.map(\.id).filter { recording.selectedIDs.contains($0) }
        return record
    }

    /// A draft invoice for `record`'s work, from Record Services' lines, and
    /// the record marked as billed on it. The record's visit, if it has one,
    /// is linked to the invoice too, as Schedule → Invoice links them, so the
    /// Schedule doesn't offer to invoice it again.
    @discardableResult
    static func invoice(_ record: ServiceRecord, lines: [InvoiceLines.Line], client: Client, operatorID: String,
                        notes: String, now: Date = .now, in context: ModelContext) -> Proposal {
        let proposal = Proposal(operatorID: operatorID, client: client)
        proposal.invoiceNumber = InvoiceNumbering.next(operatorID: operatorID, in: context)
        proposal.invoiceDueDate = now.addingTimeInterval(30 * 86_400)
        if !notes.isEmpty { proposal.notes = notes }
        let items = lines.enumerated().map { index, line in
            let item = ProposalLineItem(serviceName: line.serviceName, zoneLabel: line.zoneLabel,
                                        quantity: line.quantity, unitType: line.unitType,
                                        unitPrice: line.unitPrice, sortOrder: index)
            item.lineTotal = line.lineTotal
            return item
        }
        items.forEach { context.insert($0) }
        proposal.lineItems = items
        context.insert(proposal)
        record.invoiceID = proposal.id.uuidString
        if let visit = scheduledVisit(record.visitID, in: context) {
            proposal.visitID = visit.id.uuidString
            // Unless the visit is on another document that still exists.
            if document(visit.proposalID, in: context) == nil { visit.proposalID = proposal.id.uuidString }
        }
        return proposal
    }

    /// After an invoice was made for a scheduled visit: the visit's record,
    /// if it has one, is billed on it. (One made later is billed when it's
    /// made: `billFromVisit`.)
    static func markVisitInvoiced(visitID: String, invoice: Proposal, in context: ModelContext) {
        guard invoice.isInvoice, let id = UUID(uuidString: visitID),
              let record = record(forKey: visitKey(id), in: context),
              self.invoice(of: record, in: context) == nil else { return }
        record.invoiceID = invoice.id.uuidString
    }

    /// A revision of `original`: a copy with the next revision number, due in
    /// 30 days, that takes over its billing (`moveBilling`). The client's
    /// page and the document's page both revise through here; they used to
    /// each have their own copy of this.
    @discardableResult
    static func revise(_ original: Proposal, client: Client, now: Date = .now, in context: ModelContext) -> Proposal {
        let revision = Proposal(operatorID: original.operatorID, client: client)
        revision.invoiceNumber = InvoiceNumbering.nextRevision(of: original.invoiceNumber,
                                                               operatorID: original.operatorID, in: context)
        revision.revisionOf = original.invoiceNumber
        revision.discountAmount = original.discountAmount
        revision.taxRate = original.taxRate
        revision.disclaimer = original.disclaimer
        revision.notes = original.notes
        revision.invoiceDueDate = now.addingTimeInterval(30 * 86_400)
        let copies = original.makeLineItemCopies()
        copies.forEach { context.insert($0) }
        revision.lineItems = copies
        context.insert(revision)
        moveBilling(from: original, to: revision, in: context)
        return revision
    }

    /// A revision replaces `original`: the work billed on the original, and
    /// the visit it was made for, go to the revision, so deleting the
    /// superseded original neither unbills the work nor frees the visit to
    /// be invoiced again.
    static func moveBilling(from original: Proposal, to revision: Proposal, in context: ModelContext) {
        for record in billed(on: original, in: context) { record.invoiceID = revision.id.uuidString }
        for visit in linkedVisits(to: original, in: context) { visit.proposalID = revision.id.uuidString }
        if revision.visitID.isEmpty { revision.visitID = original.visitID }
    }

    private static func linkedVisits(to document: Proposal, in context: ModelContext) -> [ScheduledVisit] {
        let id = document.id.uuidString
        return (try? context.fetch(FetchDescriptor<ScheduledVisit>(predicate: #Predicate { $0.proposalID == id }))) ?? []
    }

    /// Deletes `document`. The work billed on it, and a visit linked to it,
    /// go back to the original if it's a revision whose original still
    /// exists; otherwise the work is unbilled again and the visit can be
    /// invoiced again from the Schedule.
    static func delete(_ document: Proposal, in context: ModelContext) {
        let original = document.revisionOf.isEmpty ? nil : (try? context.fetch(FetchDescriptor<Proposal>()))?
            .first { $0.invoiceNumber == document.revisionOf && $0.operatorID == document.operatorID
                && $0.id != document.id }
        let replacement = original?.id.uuidString ?? ""
        for record in billed(on: document, in: context) { record.invoiceID = replacement }
        for visit in linkedVisits(to: document, in: context) { visit.proposalID = replacement }
        context.delete(document)
    }

    private static func billed(on document: Proposal, in context: ModelContext) -> [ServiceRecord] {
        let id = document.id.uuidString
        return (try? context.fetch(FetchDescriptor<ServiceRecord>(predicate: #Predicate { $0.invoiceID == id }))) ?? []
    }

    // MARK: - A scheduled visit

    /// Marks `visit` complete, adds the next visit of its series if it needs
    /// one, and records the work. The record is dated when the visit was due,
    /// or now if that's still ahead: a visit ticked off the next morning was
    /// done the day before. No record for a visit without a client on file.
    @discardableResult
    static func complete(_ visit: ScheduledVisit, among visits: [ScheduledVisit], in context: ModelContext,
                         now: Date = .now) -> ServiceRecord? {
        markCompleted(visit, at: now, among: visits, in: context)

        let clientID = visit.clientID
        guard let client = try? context.fetch(FetchDescriptor<Client>()).first(where: { $0.id.uuidString == clientID })
        else { return nil }
        let record = record(forKey: visitKey(visit.id), source: .visit,
                            operatorID: visit.operatorID, client: client, in: context).record
        record.clientName = client.name
        record.propertyAddress = visit.clientAddress
        record.performedAt = min(visit.scheduledDate, now)
        record.visitID = visit.id.uuidString
        if record.lines.isEmpty {
            record.lines = lines(for: visit.expectedServiceIDs, client: client,
                                 multiplier: visit.priceMultiplier, in: context)
        }
        billFromVisit(record, visit, in: context)
        return record
    }

    /// Completed, and its series continued if it needs a next visit. A series
    /// is created up front, so its next visit usually exists already; only a
    /// series with nothing still scheduled after this visit gets one more.
    private static func markCompleted(_ visit: ScheduledVisit, at date: Date,
                                      among visits: [ScheduledVisit]? = nil, in context: ModelContext) {
        visit.status = .completed
        visit.completedAt = date
        let seriesID = visit.seriesID
        let series = visits ?? ((try? context.fetch(FetchDescriptor<ScheduledVisit>(
            predicate: #Predicate { $0.seriesID == seriesID }))) ?? [])
        ClientVisits.addNext(after: visit, among: series, in: context)
    }

    // MARK: - Services

    /// The services with these IDs, in the catalog's order, priced for the
    /// client's property the way Record Services prices them. A service since
    /// deleted from the catalog is left out: there's nothing to name it by.
    static func lines(for serviceIDs: [String], client: Client, multiplier: Double = 1,
                      in context: ModelContext) -> [ServiceRecord.Line] {
        let wanted = Set(serviceIDs)
        guard !wanted.isEmpty, let catalog = try? context.fetch(FetchDescriptor<ServiceItem>()) else { return [] }
        let zones = client.pricingZones
        return catalog
            .filter { wanted.contains($0.id.uuidString) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { service in
                ServiceRecord.Line(
                    serviceID: service.id.uuidString, name: service.name, unitType: service.unitType,
                    price: InvoiceLines.propertyPrice(unitType: service.unitType, pricePerUnit: service.pricePerUnit,
                                                      zones: zones, multiplier: multiplier))
            }
    }
}
