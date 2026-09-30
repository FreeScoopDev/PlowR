import CoreData
import Foundation
import SwiftData

/// A client's stops on routes. A stop keeps its own copy of the client's
/// name, phone, address and map pin (a route is shown and run from its
/// stops), so the stops follow the client: whenever the client is changed
/// here, whenever iCloud brings changes, at launch and whenever the app
/// comes back to the front.
///
/// They used to be copied once, when the stop was made, and never again. A
/// corrected phone number or address, or a pin set by hand, never reached
/// the routes the client was already on. Stop notes and what a run recorded
/// are the stop's own and aren't touched. The client's upcoming visits
/// follow at the same moments (ClientVisits).
enum ClientStops {
    /// The client's stops on every route. A custom stop isn't a client's.
    static func of(_ client: Client, in context: ModelContext) throws -> [RouteStop] {
        let id = client.id
        return try context.fetch(FetchDescriptor<RouteStop>(
            predicate: #Predicate { $0.clientID == id && !$0.isCustomStop }))
    }

    /// Brings `stop` in step with `client`. True when anything changed, so
    /// an unchanged stop isn't written (and synced) for nothing.
    @discardableResult
    static func follow(_ stop: RouteStop, _ client: Client) -> Bool {
        var changed = false
        if stop.clientName != client.name { stop.clientName = client.name; changed = true }
        if stop.clientPhone != client.phone { stop.clientPhone = client.phone; changed = true }
        if stop.clientAddress != client.address { stop.clientAddress = client.address; changed = true }
        if stop.latitude != client.latitude { stop.latitude = client.latitude; changed = true }
        if stop.longitude != client.longitude { stop.longitude = client.longitude; changed = true }
        return changed
    }

    /// After `client` was changed: all their stops follow, and their
    /// upcoming visits.
    static func update(for client: Client) {
        ClientVisits.update(for: client)
        guard let context = client.modelContext, let stops = try? of(client, in: context) else { return }
        for stop in stops { follow(stop, client) }
    }

    /// Every client's stops in step with the client: stops made before stops
    /// followed their client, a client changed on another device (an older
    /// PlowR there doesn't move the stops), or a stop made there from its
    /// older copy of the client. Their upcoming visits too (ClientVisits).
    /// Saves only when a stop or a visit changed.
    static func updateAll(in context: ModelContext) {
        guard let clients = try? context.fetch(FetchDescriptor<Client>()),
              let stops = try? context.fetch(FetchDescriptor<RouteStop>()) else { return }
        let byID = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = ClientVisits.updateAll(in: context)
        for stop in stops where !stop.isCustomStop {
            if let client = byID[stop.clientID], follow(stop, client) { changed = true }
        }
        if changed { try? context.save() }
    }

    /// From now on, `updateAll` whenever iCloud brings changes, `delay`
    /// after the last notice of a burst: an import is many changes, and the
    /// app's own context takes them in after the notice. A route app can
    /// stay open for days, so launch alone isn't enough.
    @discardableResult
    static func followRemoteChanges(of container: ModelContainer,
                                    center: NotificationCenter = .default,
                                    after delay: Duration = .seconds(1)) -> NSObjectProtocol {
        let sweep = Sweep(container: container, delay: delay)
        return center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sweep.schedule() }
        }
    }

    /// One `updateAll`, `delay` after the latest request.
    private final class Sweep {
        let container: ModelContainer
        let delay: Duration
        private var pending: Task<Void, Never>?

        init(container: ModelContainer, delay: Duration) {
            self.container = container
            self.delay = delay
        }

        func schedule() {
            pending?.cancel()
            pending = Task { [container, delay] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                ClientStops.updateAll(in: container.mainContext)
                // Another device's records of the same work have arrived, or
                // the invoice of a visit copied into the log before it had.
                ServiceLog.mergeDuplicates(in: container.mainContext)
                ServiceLog.linkEarlierVisits(in: container.mainContext)
            }
        }
    }
}
