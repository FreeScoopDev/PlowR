import Foundation
import SwiftData

/// Taking a client off their routes: when they're marked inactive, or
/// deleted. A deleted client's visits still ahead go too, and so do their
/// photos (only the client's page shows them). Their invoices, proposals
/// and past visits are kept or deleted, as the user chooses.
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
    /// (routes don't mark visits complete, so a visit done from a route is
    /// still "scheduled"), and so is a visit already completed.
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
    /// (Joe's call). Returns how many stops came off.
    @discardableResult
    static func takeInactiveClientsOffRoutes(in context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: inactiveCleanupKey),
              let clients = try? context.fetch(FetchDescriptor<Client>()) else { return 0 }
        var removed = 0
        for client in clients where !client.isActive {
            removed += takeOffRoutes(client, in: context)
        }
        if removed > 0 { try? context.save() }
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
