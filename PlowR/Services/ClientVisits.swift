import Foundation
import SwiftData

/// A client's upcoming visits follow the client. A visit keeps its own copy
/// of the client's name and address (the schedule and the "PlowR" calendar
/// show it), so the visits still ahead (`ClientRemoval.isAhead`) take a
/// changed name or address. Past visits keep theirs: a record of where the
/// work was done. They go with ClientStops: every place that brings a
/// client's stops in step brings their upcoming visits in step too.
///
/// A visit used to keep the name and address it was booked with, so a
/// client who moved was still due at their old house, and the calendar
/// event pointed there.
enum ClientVisits {
    /// The client's visits still ahead on the schedule.
    static func upcoming(of client: Client, in context: ModelContext, now: Date = .now) throws -> [ScheduledVisit] {
        let id = client.id.uuidString
        return try context.fetch(FetchDescriptor<ScheduledVisit>(predicate: #Predicate { $0.clientID == id }))
            .filter { ClientRemoval.isAhead($0, now: now) }
    }

    /// Brings `visit` in step with `client`. True when anything changed, so
    /// an unchanged visit isn't written (and synced) for nothing.
    @discardableResult
    static func follow(_ visit: ScheduledVisit, _ client: Client) -> Bool {
        var changed = false
        if visit.clientName != client.name { visit.clientName = client.name; changed = true }
        if visit.clientAddress != client.address { visit.clientAddress = client.address; changed = true }
        return changed
    }

    /// After `client` was changed: their upcoming visits follow.
    static func update(for client: Client, now: Date = .now) {
        guard let context = client.modelContext, let visits = try? upcoming(of: client, in: context, now: now) else { return }
        for visit in visits { follow(visit, client) }
    }

    /// Every client's upcoming visits in step with the client. True when any
    /// changed; the caller saves.
    static func updateAll(in context: ModelContext, now: Date = .now) -> Bool {
        guard let clients = try? context.fetch(FetchDescriptor<Client>()),
              let visits = try? context.fetch(FetchDescriptor<ScheduledVisit>()) else { return false }
        let byID = Dictionary(clients.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for visit in visits where ClientRemoval.isAhead(visit, now: now) {
            if let client = byID[visit.clientID], follow(visit, client) { changed = true }
        }
        return changed
    }
}
