import Foundation
import SwiftData

/// Taking a client off their routes: when they're marked inactive, or
/// deleted. A deleted client's visits still ahead go too, and so do their
/// photos (only the client's page shows them). Their invoices, proposals,
/// past visits and Service Log are kept or deleted, as the user chooses.
///
/// Deleting a client used to leave their stops on every route, though the
/// prompt said they'd be removed, and their visits on the schedule. An
/// inactive client stayed on the routes built before.
enum ClientRemoval {
    /// What taking a client off their routes, or deleting them, touches:
    /// said before it happens.
    struct Footprint: Equatable {
        /// The routes with a stop for them, by name.
        var routeNames: [String] = []
        /// Still ahead on the schedule (`isAhead`).
        var visitsAhead = 0
        var documents = 0
        var pastVisits = 0
        var photos = 0

        /// What "Keep Records" keeps.
        var hasRecords: Bool { documents + pastVisits > 0 }
    }

    /// A visit still ahead on the schedule: dated from `now` on and not
    /// completed. It goes with the client. Anything dated earlier is history
    /// (a visit done on a route is still "scheduled" unless it was the
    /// client's one visit that day), and so is a visit already completed.
    static func isAhead(_ visit: ScheduledVisit, now: Date) -> Bool {
        visit.scheduledDate >= now && visit.status != .completed
    }

    static func footprint(of client: Client, in context: ModelContext, now: Date = .now) -> Footprint {
        let id = client.id.uuidString
        let stops = (try? ClientStops.of(client, in: context)) ?? []
        var seen = Set<PersistentIdentifier>()
        let routes = stops.compactMap(\.route).filter { seen.insert($0.persistentModelID).inserted }
        let visits = self.visits(of: id, in: context)
        let ahead = visits.filter { isAhead($0, now: now) }.count
        return Footprint(
            routeNames: routes.map(\.name).sorted(),
            visitsAhead: ahead,
            documents: documents(of: id, in: context).count,
            pastVisits: visits.count - ahead,
            photos: photos(of: id, in: context).count)
    }

    /// Takes `client` off every route: their stops are deleted. Marking
    /// them active again doesn't put them back.
    @discardableResult
    static func takeOffRoutes(_ client: Client, in context: ModelContext) -> Int {
        let stops = (try? ClientStops.of(client, in: context)) ?? []
        for stop in stops { context.delete(stop) }
        return stops.count
    }

    static let inactiveCleanupKey = "inactiveClientsTakenOffRoutes"

    /// Once, at the first launch of this version: clients marked inactive
    /// before that meant coming off their routes are taken off them too
    /// (Joe's call). Returns how many stops came off. Not done yet while the
    /// store has no clients (a new phone, before iCloud has brought them) or
    /// if the save fails: it tries again at the next launch.
    @discardableResult
    static func takeInactiveClientsOffRoutes(in context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: inactiveCleanupKey),
              let clients = try? context.fetch(FetchDescriptor<Client>()), !clients.isEmpty else { return 0 }
        var removed = 0
        for client in clients where !client.isActive {
            removed += takeOffRoutes(client, in: context)
        }
        if removed > 0 {
            do { try context.save() } catch { return removed }
        }
        defaults.set(true, forKey: inactiveCleanupKey)
        return removed
    }

    /// Marks `client` active or inactive; inactive takes them off every route.
    /// The client list and Edit Client both go through here.
    static func setActive(_ active: Bool, for client: Client, in context: ModelContext) {
        if client.isActive, !active { takeOffRoutes(client, in: context) }
        client.isActive = active
        try? context.save()
    }

    /// Deletes `client`: off every route, with their visits still ahead and
    /// their photos, and their invoices, proposals and past visits kept for
    /// the books or deleted.
    static func delete(_ client: Client, keepingRecords: Bool, in context: ModelContext, now: Date = .now) {
        let id = client.id.uuidString
        takeOffRoutes(client, in: context)
        for visit in visits(of: id, in: context) {
            if !keepingRecords || isAhead(visit, now: now) {
                context.delete(visit)
            } else {
                // History now: marking it complete mustn't continue its series
                // for a client who's gone.
                visit.isRecurring = false
            }
        }
        if !keepingRecords {
            for document in documents(of: id, in: context) { context.delete(document) }
            for record in ServiceLog.records(ofClient: id, in: context) { context.delete(record) }
        }
        for photo in photos(of: id, in: context) { context.delete(photo) }
        context.delete(client)
        try? context.save()
    }

    // MARK: - What the prompts say

    /// Marking a client inactive, when they're on a route.
    static func deactivateMessage(for footprint: Footprint, locale: Locale = .current) -> String {
        "They'll be taken off \(routes(footprint.routeNames, locale)). Marking them active again won't put them back."
    }

    /// Deleting a client. An active one could be marked inactive instead.
    static func deleteMessage(for footprint: Footprint, isActive: Bool, locale: Locale = .current) -> String {
        var sentences: [String] = []
        if !footprint.routeNames.isEmpty {
            sentences.append("They'll be taken off \(routes(footprint.routeNames, locale)).")
        }
        let goes = [
            footprint.visitsAhead > 0 ? count(footprint.visitsAhead, "upcoming visit", "upcoming visits") : nil,
            footprint.photos > 0 ? count(footprint.photos, "photo", "photos") : nil,
        ].compactMap { $0 }
        if !goes.isEmpty {
            sentences.append("Their \(goes.formatted(.list(type: .and).locale(locale))) will be deleted with them.")
        }
        if footprint.hasRecords {
            let records = [
                footprint.documents > 0 ? count(footprint.documents, "invoice or proposal", "invoices or proposals") : nil,
                footprint.pastVisits > 0 ? count(footprint.pastVisits, "past visit", "past visits") : nil,
            ].compactMap { $0 }
            sentences.append("Keep their \(records.formatted(.list(type: .and).locale(locale))) for your records, "
                + "or delete everything?")
        } else {
            sentences.append("This can't be undone.")
        }
        if isActive {
            sentences.append(footprint.routeNames.isEmpty
                ? "To keep them and their history, mark them Inactive instead."
                : "To keep them and their history, mark them Inactive instead: that takes them off their routes too.")
        }
        return sentences.joined(separator: " ")
    }

    private static func routes(_ names: [String], _ locale: Locale) -> String {
        names.count == 1 ? "the route \(names[0])"
            : "\(names.count) routes: \(names.formatted(.list(type: .and).locale(locale)))"
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    // MARK: - A client's records

    private static func visits(of clientID: String, in context: ModelContext) -> [ScheduledVisit] {
        (try? context.fetch(FetchDescriptor<ScheduledVisit>(predicate: #Predicate { $0.clientID == clientID }))) ?? []
    }

    private static func documents(of clientID: String, in context: ModelContext) -> [Proposal] {
        (try? context.fetch(FetchDescriptor<Proposal>(predicate: #Predicate { $0.clientID == clientID }))) ?? []
    }

    private static func photos(of clientID: String, in context: ModelContext) -> [StopPhoto] {
        (try? context.fetch(FetchDescriptor<StopPhoto>(predicate: #Predicate { $0.clientID == clientID }))) ?? []
    }
}

/// Removing one of a client's additional properties: its stops come off
/// their routes and its visits not done yet from the start of today are
/// deleted (as ClientVisits follows them: one left behind would have nowhere
/// to be); its done visits, jobs, invoices and photos stay as the client's
/// history. Only the property's client's: a visit is matched by client and
/// property both.
enum PropertyRemoval {
    /// How many stops and upcoming visits removing `property` takes with it.
    static func footprint(of property: Property, in context: ModelContext, now: Date = .now) -> (stops: Int, visits: Int) {
        (stops(of: property, in: context).count, visitsLeft(of: property, in: context, now: now).count)
    }

    static func remove(_ property: Property, in context: ModelContext, now: Date = .now) {
        stops(of: property, in: context).forEach { context.delete($0) }
        visitsLeft(of: property, in: context, now: now).forEach { context.delete($0) }
        context.delete(property)
        try? context.save()
    }

    private static func stops(of property: Property, in context: ModelContext) -> [RouteStop] {
        let id = property.id.uuidString
        let clientID = property.client?.id
        let stops = (try? context.fetch(FetchDescriptor<RouteStop>(predicate: #Predicate { $0.propertyID == id }))) ?? []
        return stops.filter { $0.clientID == clientID }
    }

    private static func visitsLeft(of property: Property, in context: ModelContext, now: Date) -> [ScheduledVisit] {
        let id = property.id.uuidString
        let clientID = property.client?.id.uuidString ?? ""
        let visits = (try? context.fetch(FetchDescriptor<ScheduledVisit>(predicate: #Predicate {
            $0.propertyID == id && $0.clientID == clientID
        }))) ?? []
        return visits.filter { ClientVisits.follows($0, now: now) }
    }
}
