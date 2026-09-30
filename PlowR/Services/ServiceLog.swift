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

    /// The record for `key`, made (for `client`) if there isn't one yet. A
    /// new record is billable unless the client is comped: that is decided
    /// when the work is done, not changed later.
    private static func record(forKey key: String, source: ServiceRecordSource, operatorID: String,
                               client: Client, in context: ModelContext) -> ServiceRecord {
        if let existing = record(forKey: key, in: context) { return existing }
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
    /// If the client has exactly one visit that day, it's completed too and
    /// shares the record (`visitForStop`).
    @discardableResult
    static func recordStop(_ stop: RouteStop, of client: Client, run: UUID, operatorID: String,
                           startedAt: Date, finishedAt: Date, minutes: Double, in context: ModelContext,
                           calendar: Calendar = .current) -> ServiceRecord {
        let visit = visitForStop(of: client, run: run, on: finishedAt, in: context, calendar: calendar)
        let key = visit.map { visitKey($0.id) } ?? stopKey(run: run, stop: stop.id)
        let record = record(forKey: key, source: .route, operatorID: operatorID, client: client, in: context)
        if let visit {
            if visit.status == .scheduled { markCompleted(visit, at: finishedAt, in: context) }
            record.visitID = visit.id.uuidString
            record.source = .route
        }
        record.clientName = client.name
        record.propertyAddress = stop.clientAddress
        record.startedAt = startedAt
        record.performedAt = finishedAt
        record.minutes = max(0, minutes)
        record.routeID = stop.route?.id.uuidString ?? ""
        record.routeName = stop.route?.name ?? ""
        record.runID = run.uuidString
        record.stopID = stop.id.uuidString
        if !stop.completedServiceIDs.isEmpty {
            record.lines = lines(for: stop.completedServiceIDs, client: client, in: context)
        }
        if !stop.completedNotes.isEmpty { record.notes = stop.completedNotes }
        return record
    }

    /// The client's visit that a stop completed on `day` by run `run` is:
    /// their only visit that day that's scheduled or done. None when there
    /// are two or more (which one was it?), or when that visit was already
    /// done by another run of a route (a second pass is its own work).
    static func visitForStop(of client: Client, run: UUID, on day: Date, in context: ModelContext,
                             calendar: Calendar = .current) -> ScheduledVisit? {
        let clientID = client.id.uuidString
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let descriptor = FetchDescriptor<ScheduledVisit>(predicate: #Predicate {
            $0.clientID == clientID && $0.scheduledDate >= start && $0.scheduledDate < end
        })
        let sameDay = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.status == .scheduled || $0.status == .completed }
        guard sameDay.count == 1, let visit = sameDay.first else { return nil }
        guard visit.status == .completed, let done = record(forKey: visitKey(visit.id), in: context) else { return visit }
        // Done from the Schedule (no run), or earlier on this same run.
        return done.runID.isEmpty || done.runID == run.uuidString ? visit : nil
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
                            operatorID: visit.operatorID, client: client, in: context)
        record.clientName = client.name
        record.propertyAddress = visit.clientAddress
        record.performedAt = min(visit.scheduledDate, now)
        record.visitID = visit.id.uuidString
        if record.lines.isEmpty {
            record.lines = lines(for: visit.expectedServiceIDs, client: client,
                                 multiplier: visit.priceMultiplier, in: context)
        }
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
