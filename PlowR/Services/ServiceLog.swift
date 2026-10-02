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
        let descriptor = FetchDescriptor<ServiceRecord>(predicate: #Predicate { $0.sourceKey == key })
        return oldest((try? context.fetch(descriptor)) ?? [])
    }

    /// The oldest of `records` by creation, then by ID: every device picks
    /// the same one, even from two made in the same instant.
    static func oldest(_ records: [ServiceRecord]) -> ServiceRecord? {
        records.min { isOlder($0, than: $1) }
    }

    private static func isOlder(_ a: ServiceRecord, than b: ServiceRecord) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
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
        return (newRecord(forKey: key, source: source, operatorID: operatorID, client: client, in: context), true)
    }

    /// A new record for `client`'s work, inserted. Billable unless the client
    /// is comped: that is decided when the work is done, not changed later.
    private static func newRecord(forKey key: String, source: ServiceRecordSource, operatorID: String,
                                  client: Client, in context: ModelContext) -> ServiceRecord {
        let record = ServiceRecord(operatorID: operatorID, sourceKey: key, source: source)
        record.clientID = client.id.uuidString
        // A client's main property will have the client's ID (Properties).
        record.propertyID = client.id.uuidString
        record.isBillable = !client.isComped
        context.insert(record)
        return record
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
            record.lines = lines(for: stop.completedServiceIDs, client: client, propertyID: stop.propertyID,
                                 in: context)
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
            visit.serviceLogged = true
            billFromVisit(record, visit, in: context)
        }
        record.clientName = client.name
        record.propertyID = Place.id(of: client, propertyID: stop.propertyID)
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
        runRecord(run: run, stop: stop.id, in: context)
    }

    /// The record run `run` has for the stop with ID `stop`, whatever its key
    /// (a stop that shared the day's visit is under the visit's). Found by
    /// IDs, so the stop itself can be gone.
    static func runRecord(run: UUID, stop: UUID, in context: ModelContext) -> ServiceRecord? {
        let runID = run.uuidString
        let stopID = stop.uuidString
        let descriptor = FetchDescriptor<ServiceRecord>(
            predicate: #Predicate { $0.runID == runID && $0.stopID == stopID })
        return oldest((try? context.fetch(descriptor)) ?? [])
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
        // At the same place: the rental's visit isn't the main house's stop.
        // Compared by ID, found or not: a removed property's visit is never the main house's.
        let place = Place.id(of: client, propertyID: stop.propertyID)
        let sameDay = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.status == .scheduled || $0.status == .completed }
            .filter { Place.id(of: client, propertyID: $0.propertyID) == place }
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
        billingStatus(of: record, in: context) == .notBilled
    }

    /// Where a job stands with billing: the one status Service History shows.
    enum BillingStatus: Equatable {
        case invoiced, notTracked, noCharge, covered, notBilled
    }

    /// On an invoice; else from before the log (never counted as owed); else
    /// no charge; else covered by a contract (nothing of it charged by the
    /// visit); else not billed yet.
    static func billingStatus(of record: ServiceRecord, in context: ModelContext) -> BillingStatus {
        billingStatus(of: record, invoiced: invoice(of: record, in: context) != nil,
                      covered: isCovered(record, contracts: Contracts.all(in: context)))
    }

    /// The rule itself, given whether the record's invoice exists and whether
    /// a contract covers all of it: for checking many records against one
    /// lookup of the invoices (`invoiceIDs`) and contracts.
    static func billingStatus(of record: ServiceRecord, invoiced: Bool, covered: Bool) -> BillingStatus {
        if invoiced { return .invoiced }
        if record.source == .beforeLog { return .notTracked }
        if !record.isBillable { return .noCharge }
        return covered ? .covered : .notBilled
    }

    /// What a job charges (Contracts.charge): its services as recorded,
    /// unless a contract covers it.
    static func charge(of record: ServiceRecord, contracts: [Contract]) -> [ServiceRecord.Line] {
        Contracts.charge(of: record.lines, under: Contracts.contract(covering: record, among: contracts))
    }

    /// A job with services, none of them charged by the visit: a season or
    /// monthly contract covers all of it.
    static func isCovered(_ record: ServiceRecord, contracts: [Contract]) -> Bool {
        !record.lines.isEmpty && charge(of: record, contracts: contracts).isEmpty
    }

    /// The IDs of every invoice (not proposal) there is, looked up once.
    static func invoiceIDs(in context: ModelContext) -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<Proposal>())) ?? []).filter(\.isInvoice).map(\.id.uuidString))
    }

    /// Whether the work of `visit` is already on an invoice, so the Schedule
    /// mustn't offer to invoice the visit again.
    static func isVisitBilled(_ visit: ScheduledVisit, in context: ModelContext) -> Bool {
        guard let record = record(forKey: visitKey(visit.id), in: context) else { return false }
        return invoice(of: record, in: context) != nil
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

    /// `record` for `visit`'s work, done for `client`: who and where (the
    /// visit's address), when, the visit's expected services priced for the
    /// property, and the invoice made for the visit if there is one.
    /// Completing a visit and copying in one done before the log both fill a
    /// record through here, so the two can't differ. `catalog` and
    /// `documents` are for a caller filling many at once.
    private static func fill(_ record: ServiceRecord, from visit: ScheduledVisit, client: Client, performedAt: Date,
                             catalog: [ServiceItem]? = nil, documents: [String: Proposal]? = nil,
                             in context: ModelContext) {
        record.clientName = client.name
        record.propertyID = Place.id(of: client, propertyID: visit.propertyID)
        record.propertyAddress = visit.clientAddress
        record.performedAt = performedAt
        record.visitID = visit.id.uuidString
        visit.serviceLogged = true
        if record.lines.isEmpty {
            record.lines = lines(for: visit.expectedServiceIDs, client: client, propertyID: visit.propertyID,
                                 multiplier: visit.priceMultiplier, catalog: catalog, in: context)
        }
        if let documents {
            if record.invoiceID.isEmpty, let invoice = documents[visit.proposalID], invoice.isInvoice {
                record.invoiceID = invoice.id.uuidString
            }
        } else {
            billFromVisit(record, visit, in: context)
        }
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
        let items = lines.enumerated().map { index, line in
            let item = ProposalLineItem(serviceName: line.serviceName, zoneLabel: line.zoneLabel,
                                        quantity: line.quantity, unitType: line.unitType,
                                        unitPrice: line.unitPrice, sortOrder: index)
            item.lineTotal = line.lineTotal
            return item
        }
        let proposal = newDraftInvoice(for: client, items: items, operatorID: operatorID, notes: notes,
                                       now: now, in: context)
        record.invoiceID = proposal.id.uuidString
        if let visit = scheduledVisit(record.visitID, in: context) {
            proposal.visitID = visit.id.uuidString
            link(visit, to: proposal, in: context)
        }
        return proposal
    }

    /// How long a new invoice gives to pay.
    static let invoiceTerm: TimeInterval = 30 * 86_400

    /// A new draft invoice for `client` with `items`: the next number, due in
    /// `invoiceTerm`, the business's default terms. Record Services and Bill
    /// Unbilled Work both make invoices through here, so they can't differ.
    static func newDraftInvoice(for client: Client, items: [ProposalLineItem], operatorID: String,
                                notes: String = "", now: Date, in context: ModelContext) -> Proposal {
        let proposal = Proposal(operatorID: operatorID, client: client)
        proposal.invoiceNumber = InvoiceNumbering.next(operatorID: operatorID, in: context)
        proposal.invoiceDueDate = now.addingTimeInterval(invoiceTerm)
        let profile = (try? context.fetch(FetchDescriptor<BusinessProfile>()))?.first { $0.operatorID == operatorID }
        proposal.disclaimer = profile?.defaultDisclaimer ?? ""
        if !notes.isEmpty { proposal.notes = notes }
        items.forEach { context.insert($0) }
        proposal.lineItems = items
        context.insert(proposal)
        return proposal
    }

    /// `visit` is on `proposal` now, unless it's on another document that
    /// still exists, so the Schedule doesn't offer to invoice it again.
    static func link(_ visit: ScheduledVisit, to proposal: Proposal, in context: ModelContext) {
        if document(visit.proposalID, in: context) == nil { visit.proposalID = proposal.id.uuidString }
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
        revision.invoiceDueDate = now.addingTimeInterval(invoiceTerm)
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
        // A contract payment's revision is still that payment.
        revision.contractID = original.contractID
        revision.installmentIndex = original.installmentIndex
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

    // MARK: - A client's Service History

    /// Work done off a route or a visit, logged from the client's Service
    /// History, at the client's address.
    /// Not dated in the future: it's work done.
    @discardableResult
    static func logWork(_ recording: StopRecording, notes: String, performedAt: Date, minutes: Double,
                        for client: Client, at propertyID: String = "", operatorID: String, now: Date = .now,
                        in context: ModelContext) -> ServiceRecord {
        let record = record(forKey: "manual:\(UUID().uuidString)", source: .manual, operatorID: operatorID,
                            client: client, in: context).record
        record.clientName = client.name
        // At the place chosen: the client's own address, or a property.
        record.propertyID = Place.id(of: client, propertyID: propertyID)
        record.propertyAddress = Place.of(client, propertyID: propertyID)?.address ?? client.address
        record.performedAt = min(performedAt, now)
        record.minutes = max(0, minutes)
        record.lines = recording.recordLines
        record.notes = notes
        return record
    }

    /// Changes made on a record's own page. While it's on an invoice its
    /// services (`servicesLocked`) and whether it's billable stay as they
    /// are: they're what the bill says. Change the invoice instead. Never
    /// dated in the future.
    static func update(_ record: ServiceRecord, lines: [ServiceRecord.Line], notes: String, performedAt: Date,
                       minutes: Double, isBillable: Bool, now: Date = .now, in context: ModelContext) {
        record.notes = notes
        record.performedAt = min(performedAt, now)
        record.minutes = max(0, minutes)
        if !servicesLocked(record, in: context) { record.lines = lines }
        if invoice(of: record, in: context) == nil { record.isBillable = isBillable }
    }

    /// Deletes `record`, unless it's on an invoice: delete the invoice first,
    /// or the bill would name work the log no longer has. Its photos stay in
    /// the client's gallery. True if it was deleted.
    @discardableResult
    static func deleteRecord(_ record: ServiceRecord, in context: ModelContext) -> Bool {
        guard invoice(of: record, in: context) == nil else { return false }
        for photo in photos(of: record, in: context) { photo.recordID = "" }
        context.delete(record)
        return true
    }

    /// The photos taken for `record`'s work, oldest first.
    static func photos(of record: ServiceRecord, in context: ModelContext) -> [StopPhoto] {
        let id = record.id.uuidString
        let descriptor = FetchDescriptor<StopPhoto>(predicate: #Predicate { $0.recordID == id })
        return StopPhoto.ordered((try? context.fetch(descriptor)) ?? [])
    }

    /// The operator's active services, in catalog order, as the Service Log
    /// forms list them.
    static func activeServices(_ all: [ServiceItem], operatorID: String) -> [StopRecording.Service] {
        all.filter { $0.operatorID == operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { .init(id: $0.id.uuidString, name: $0.name, unitType: $0.unitType, pricePerUnit: $0.pricePerUnit) }
    }

    /// What a record's work adds up to.
    static func total(of record: ServiceRecord) -> Double {
        InvoiceLines.roundedToCent(record.lines.reduce(0) { $0 + $1.price })
    }

    // MARK: - Keeping the log whole

    /// How many visits one backfill pass handles before saving: a launch cut
    /// short keeps what's done, and the app gets the main thread back
    /// between passes.
    static let backfillBatch = 200

    /// Visits completed without a Service Log record get one, so a client's
    /// Service History starts with the work already done: visits completed
    /// before the log existed, or on a device still running an older PlowR.
    /// Each is a `.beforeLog` record, "Billing Not Tracked": PlowR can only
    /// tell such work was billed if the invoice was made for the visit
    /// (Schedule → Invoice), so it's never counted as owed (Joe's call).
    ///
    /// Each visit's synced `serviceLogged` mark says it's been done, so it's
    /// done once per visit, on whichever device gets there first, and a job
    /// the user deleted is never made again. Dated when the visit was due (or
    /// completed, if earlier), priced at today's catalog prices (the prices
    /// then weren't kept). A visit whose client isn't on this device yet
    /// waits for a later launch. (Route runs from before the log can't be
    /// recovered: each run wiped the one before.)
    ///
    /// One pass: up to `limit` visits, then a save. Returns how many visits
    /// it handled (0: nothing left, or the save failed) and how many records
    /// it made. Run it on a context of its own: a failed save rolls back.
    @discardableResult
    static func backfillCompletedVisits(in context: ModelContext,
                                        limit: Int = backfillBatch) -> (handled: Int, made: Int) {
        let completed = VisitStatus.completed.rawValue
        guard let unlogged = try? context.fetch(FetchDescriptor<ScheduledVisit>(
                  predicate: #Predicate { $0.statusRaw == completed && !$0.serviceLogged })),
              !unlogged.isEmpty,
              let clients = try? context.fetch(FetchDescriptor<Client>()) else { return (0, 0) }
        let clientsByID = Dictionary(clients.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        // Visits of a client not on this device (yet, or deleted keeping the
        // records) wait; with none to do, nothing more is fetched.
        let visits = unlogged.filter { clientsByID[$0.clientID] != nil }.prefix(max(1, limit))
        guard !visits.isEmpty, let existing = try? context.fetch(FetchDescriptor<ServiceRecord>()) else { return (0, 0) }
        // Looked up once per pass, not per visit.
        let logged = Set(existing.map(\.sourceKey))
        let catalog = (try? context.fetch(FetchDescriptor<ServiceItem>())) ?? []
        let documents = Dictionary(((try? context.fetch(FetchDescriptor<Proposal>())) ?? [])
            .map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        var made = 0
        for visit in visits {
            guard let client = clientsByID[visit.clientID] else { continue }
            let key = visitKey(visit.id)
            if logged.contains(key) {
                visit.serviceLogged = true
            } else {
                let record = newRecord(forKey: key, source: .beforeLog, operatorID: visit.operatorID,
                                       client: client, in: context)
                fill(record, from: visit, client: client,
                     performedAt: min(visit.scheduledDate, visit.completedAt ?? visit.scheduledDate),
                     catalog: catalog, documents: documents, in: context)
                made += 1
            }
        }
        return save(context) ? (visits.count, made) : (0, 0)
    }

    /// Every backfill pass there is to do, on a context of its own, giving
    /// the main thread back between passes. For launch.
    static func backfillAll(in container: ModelContainer) async {
        let context = ModelContext(container)
        await Task.yield()
        while backfillCompletedVisits(in: context).handled > 0 {
            await Task.yield()
        }
    }

    /// Jobs copied in before their visit's invoice or the catalog had arrived
    /// from iCloud (or invoiced since, on an older PlowR) catch up: the
    /// visit's invoice, and its expected services if the job has none. Runs
    /// after each iCloud import. Saves only if anything changed; returns how
    /// many jobs it updated.
    @discardableResult
    static func linkEarlierVisits(in context: ModelContext) -> Int {
        let beforeLog = ServiceRecordSource.beforeLog.rawValue
        guard let records = try? context.fetch(FetchDescriptor<ServiceRecord>(
                  predicate: #Predicate { $0.sourceRaw == beforeLog })), !records.isEmpty,
              let visits = try? context.fetch(FetchDescriptor<ScheduledVisit>()),
              let clients = try? context.fetch(FetchDescriptor<Client>()) else { return 0 }
        let visitsByID = Dictionary(visits.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let clientsByID = Dictionary(clients.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        var updated = 0
        for record in records {
            guard let visit = visitsByID[record.visitID] else { continue }
            var changed = false
            if invoice(of: record, in: context) == nil, let invoice = invoice(ofVisit: visit, in: context),
               record.invoiceID != invoice.id.uuidString {
                record.invoiceID = invoice.id.uuidString
                changed = true
            }
            if record.lines.isEmpty, !visit.expectedServiceIDs.isEmpty, let client = clientsByID[record.clientID] {
                let lines = lines(for: visit.expectedServiceIDs, client: client, propertyID: visit.propertyID,
                                  multiplier: visit.priceMultiplier, in: context)
                if !lines.isEmpty {
                    record.lines = lines
                    changed = true
                }
            }
            if changed { updated += 1 }
        }
        if updated > 0 { try? context.save() }
        return updated
    }

    /// Saves, or leaves nothing half-made to be saved with the user's next change.
    private static func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    /// How long a duplicate is left before it's merged: long enough for the
    /// day's route to finish writing to it. Merged sooner, a photo or the
    /// stop's times saved to it on a device that hasn't heard of the merge
    /// yet would land on a deleted record.
    static let mergeAfter: TimeInterval = 24 * 3_600

    /// Merges records of the same work: two devices that each recorded it
    /// before syncing (CloudKit can't enforce a unique key) each made one.
    /// The oldest stays (the one `record(forKey:)` has been updating) and
    /// takes from the others what it lacks: an invoice together with the
    /// services it billed; the services a route recorded, over a visit's
    /// expected ones (or over a visit record's services edited by hand: the
    /// merge can't tell those apart); notes; the route's times and GPS
    /// arrival and departure. Their photos
    /// move to it.
    /// A copy is merged only once it's `mergeAfter` old, and never when both
    /// are on different invoices: that double bill is real and stays in
    /// sight. (Work logged by hand has a key of its own each time, so it
    /// never merges.) Saves only if anything merged; returns how many went.
    @discardableResult
    static func mergeDuplicates(in context: ModelContext, now: Date = .now) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<ServiceRecord>()) else { return 0 }
        var survivors: [String: ServiceRecord] = [:]
        var merged = 0
        for record in all.sorted(by: { isOlder($0, than: $1) }) where !record.sourceKey.isEmpty {
            guard let survivor = survivors[record.sourceKey] else {
                survivors[record.sourceKey] = record
                continue
            }
            guard now.timeIntervalSince(record.createdAt) >= mergeAfter else { continue }
            let survivorInvoice = invoice(of: survivor, in: context)
            let copyInvoice = invoice(of: record, in: context)
            if let survivorInvoice, let copyInvoice, survivorInvoice.id != copyInvoice.id { continue }
            if survivorInvoice == nil, copyInvoice != nil {
                survivor.invoiceID = record.invoiceID
                // Billed lines win: the survivor must match the bill it takes.
                // An invoice with no services on the copy (made ahead, for the
                // visit) bills whatever the survivor recorded.
                if !record.lines.isEmpty { survivor.servicesData = record.servicesData }
            } else if !servicesLocked(survivor, in: context), !record.lines.isEmpty,
                      survivor.lines.isEmpty || (survivor.startedAt == nil && record.startedAt != nil) {
                survivor.servicesData = record.servicesData
            }
            // Work that was tracked (from a route or the Schedule) wins over a
            // copy made before the log: which device was quicker mustn't
            // decide whether it's owed.
            if survivor.source == .beforeLog, record.source != .beforeLog { survivor.source = record.source }
            if survivor.notes.isEmpty { survivor.notes = record.notes }
            if survivor.startedAt == nil, let started = record.startedAt {
                survivor.source = .route
                survivor.startedAt = started
                survivor.performedAt = record.performedAt
                survivor.minutes = record.minutes
            }
            // GPS arrival and departure: only the crew's copy has them.
            if survivor.arrivedAt == nil { survivor.arrivedAt = record.arrivedAt }
            if survivor.leftAt == nil { survivor.leftAt = record.leftAt }
            if survivor.runID.isEmpty {
                survivor.runID = record.runID
                survivor.stopID = record.stopID
                survivor.routeID = record.routeID
                survivor.routeName = record.routeName
            }
            for photo in photos(of: record, in: context) { photo.recordID = survivor.id.uuidString }
            context.delete(record)
            merged += 1
        }
        if merged > 0 { try? context.save() }
        return merged
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
        fill(record, from: visit, client: client, performedAt: min(visit.scheduledDate, now), in: context)
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
    static func lines(for serviceIDs: [String], client: Client, propertyID: String = "", multiplier: Double = 1,
                      catalog: [ServiceItem]? = nil, in context: ModelContext) -> [ServiceRecord.Line] {
        let wanted = Set(serviceIDs)
        guard !wanted.isEmpty,
              let catalog = catalog ?? (try? context.fetch(FetchDescriptor<ServiceItem>())) else { return [] }
        // Priced for the place the work was at (Place): its measured zones.
        // A missing place has none: never the main house's.
        let zones = Place.of(client, propertyID: propertyID)?.zones ?? []
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
