import Foundation
import SwiftData

/// Taking a client off their routes: when they're marked inactive, or
/// deleted. A deleted client's visits not yet done go too, and their records
/// (invoices, proposals, past visits and photos) are kept or deleted, as the
/// user chooses.
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
        /// Scheduled and not yet done, whatever the date.
        var visitsToDo = 0
        var documents = 0
        var pastVisits = 0
        var photos = 0

        var hasRecords: Bool { documents + pastVisits + photos > 0 }
    }

    static func footprint(of client: Client, in context: ModelContext) -> Footprint {
        let id = client.id.uuidString
        let stops = (try? ClientStops.of(client, in: context)) ?? []
        var seen = Set<PersistentIdentifier>()
        let routes = stops.compactMap(\.route).filter { seen.insert($0.persistentModelID).inserted }
        let visits = self.visits(of: id, in: context)
        return Footprint(
            routeNames: routes.map(\.name).sorted(),
            visitsToDo: visits.filter { $0.status == .scheduled }.count,
            documents: documents(of: id, in: context).count,
            pastVisits: visits.filter { $0.status != .scheduled }.count,
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

    /// Marks `client` inactive, off every route.
    static func deactivate(_ client: Client, in context: ModelContext) {
        client.isActive = false
        takeOffRoutes(client, in: context)
        try? context.save()
    }

    /// Deletes `client`: off every route, their visits not yet done deleted,
    /// and their invoices, proposals, past visits and photos kept for the
    /// books or deleted.
    static func delete(_ client: Client, keepingRecords: Bool, in context: ModelContext) {
        let id = client.id.uuidString
        takeOffRoutes(client, in: context)
        for visit in visits(of: id, in: context) where !keepingRecords || visit.status == .scheduled {
            context.delete(visit)
        }
        if !keepingRecords {
            for document in documents(of: id, in: context) { context.delete(document) }
            for photo in photos(of: id, in: context) { context.delete(photo) }
        }
        context.delete(client)
        try? context.save()
    }

    // MARK: - What the prompts say

    /// Marking a client inactive, when they're on a route.
    static func deactivateMessage(for footprint: Footprint) -> String {
        "They'll be taken off \(routes(footprint.routeNames)). Marking them active again won't put them back."
    }

    /// Deleting a client. An active one could be marked inactive instead.
    static func deleteMessage(for footprint: Footprint, isActive: Bool) -> String {
        var sentences: [String] = []
        if !footprint.routeNames.isEmpty {
            sentences.append("They'll be taken off \(routes(footprint.routeNames)).")
        }
        if footprint.visitsToDo > 0 {
            sentences.append("\(count(footprint.visitsToDo, "visit", "visits")) not yet done will be deleted.")
        }
        if footprint.hasRecords {
            let records = [
                footprint.documents > 0 ? count(footprint.documents, "invoice or proposal", "invoices and proposals") : nil,
                footprint.pastVisits > 0 ? count(footprint.pastVisits, "past visit", "past visits") : nil,
                footprint.photos > 0 ? count(footprint.photos, "photo", "photos") : nil,
            ].compactMap { $0 }
            sentences.append("Keep their \(records.formatted(.list(type: .and))) for your records, or delete everything?")
        }
        if isActive { sentences.append("To keep the client too, mark them Inactive instead.") }
        return sentences.joined(separator: " ")
    }

    private static func routes(_ names: [String]) -> String {
        names.count == 1 ? "the route \(names[0])" : "\(names.count) routes: \(names.formatted(.list(type: .and)))"
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
