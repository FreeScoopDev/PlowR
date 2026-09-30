import Foundation
import SwiftData

/// A client's upcoming visits follow the client. A visit keeps its own copy
/// of the client's name and address (the schedule and the "PlowR" calendar
/// show it), so the visits from today on (`follows`) take a changed name or
/// address. Visits on earlier days keep theirs, as a record. They go with
/// ClientStops: every place that brings a client's stops in step brings
/// their upcoming visits in step too.
///
/// A visit used to keep the name and address it was booked with, so a
/// client who moved was still due at their old house, and the calendar
/// event pointed there.
enum ClientVisits {
    /// Whether `visit` follows its client: not completed, and dated today or
    /// later. Today's count until they're done: a route completes a visit
    /// only when it's the client's one visit that day (ServiceLog), and an
    /// address corrected during the day should reach today's visit and its
    /// calendar event. (Deleting a client goes by
    /// `ClientRemoval.isAhead` instead: from this moment on.)
    static func follows(_ visit: ScheduledVisit, now: Date = .now, calendar: Calendar = .current) -> Bool {
        visit.status != .completed && visit.scheduledDate >= calendar.startOfDay(for: now)
    }

    /// The client's visits that follow them.
    static func upcoming(of client: Client, in context: ModelContext, now: Date = .now,
                         calendar: Calendar = .current) throws -> [ScheduledVisit] {
        let id = client.id.uuidString
        let start = calendar.startOfDay(for: now)
        let completed = VisitStatus.completed.rawValue
        // Fetched by date, not every visit ever recorded; `follows` decides.
        let descriptor = FetchDescriptor<ScheduledVisit>(predicate: #Predicate {
            $0.clientID == id && $0.scheduledDate >= start && $0.statusRaw != completed
        })
        return try context.fetch(descriptor).filter { follows($0, now: now, calendar: calendar) }
    }

    /// Brings `visit` in step with `client`. True when anything changed, so
    /// an unchanged visit isn't written (and synced) for nothing.
    @discardableResult
    static func follow(_ visit: ScheduledVisit, _ client: Client) -> Bool {
        var changed = false
        if visit.clientName != client.name { visit.clientName = client.name; changed = true }
        // Its place's address (Place); a missing place's visit keeps its own.
        if let address = Place.of(client, propertyID: visit.propertyID)?.address, visit.clientAddress != address {
            visit.clientAddress = address
            changed = true
        }
        return changed
    }

    /// `visit` booked for `client` at their place with `propertyID`, as an
    /// edit of it sets it. A place that isn't the client's (the visit was
    /// moved to another client and kept the first one's) is their main
    /// address instead. Left as it was, the place is kept even if it's
    /// missing here: not synced yet isn't gone.
    static func book(_ visit: ScheduledVisit, for client: Client, at propertyID: String) {
        let unchanged = visit.clientID == client.id.uuidString && visit.propertyID == propertyID
        if !unchanged {
            visit.propertyID = Place.of(client, propertyID: propertyID)?.storedID ?? ""
        }
        visit.clientID = client.id.uuidString
        visit.clientName = client.name
        visit.clientAddress = Place.of(client, propertyID: visit.propertyID)?.address ?? visit.clientAddress
    }

    /// After `client` was changed: their upcoming visits follow.
    static func update(for client: Client, now: Date = .now, calendar: Calendar = .current) {
        guard let context = client.modelContext,
              let visits = try? upcoming(of: client, in: context, now: now, calendar: calendar) else { return }
        for visit in visits { follow(visit, client) }
    }

    /// Every client's upcoming visits in step with the client. True when any
    /// changed; the caller saves.
    static func updateAll(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: now)
        let completed = VisitStatus.completed.rawValue
        let descriptor = FetchDescriptor<ScheduledVisit>(predicate: #Predicate {
            $0.scheduledDate >= start && $0.statusRaw != completed
        })
        guard let clients = try? context.fetch(FetchDescriptor<Client>()),
              let visits = try? context.fetch(descriptor) else { return false }
        let byID = Dictionary(clients.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for visit in visits where follows(visit, now: now, calendar: calendar) {
            if let client = byID[visit.clientID], follow(visit, client) { changed = true }
        }
        return changed
    }

    /// After `visit` was completed: the next visit in its series, if the
    /// series needs one (ScheduledVisit.continuation), inserted with the
    /// client's current name and address. It was copied from the completed
    /// visit, often an earlier day's, which keeps the details it had.
    @discardableResult
    static func addNext(after visit: ScheduledVisit, among visits: [ScheduledVisit],
                        in context: ModelContext) -> ScheduledVisit? {
        guard let next = visit.continuation(among: visits) else { return nil }
        context.insert(next)
        let id = next.clientID
        if let client = try? context.fetch(FetchDescriptor<Client>()).first(where: { $0.id.uuidString == id }) {
            follow(next, client)
        }
        return next
    }
}
