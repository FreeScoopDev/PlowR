import Foundation
import SwiftData

/// A client's stops on routes. A stop keeps its own copy of the client's
/// name, phone, address and map pin (a route is shown and run from its
/// stops), so the stops follow the client: whenever the client is changed,
/// and once at launch.
///
/// They used to be copied once, when the stop was made, and never again. A
/// corrected phone number or address, or a pin set by hand, never reached
/// the routes the client was already on. Stop notes and what a run recorded
/// are the stop's own and aren't touched.
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

    /// After `client` was changed: all their stops follow.
    static func update(for client: Client) {
        guard let context = client.modelContext, let stops = try? of(client, in: context) else { return }
        for stop in stops { follow(stop, client) }
    }

    /// Every client's stops in step with the client. At launch: stops made
    /// before stops followed their client, and ones a device running an
    /// older PlowR changed through iCloud.
    static func updateAll(in context: ModelContext) {
        guard let clients = try? context.fetch(FetchDescriptor<Client>()),
              let stops = try? context.fetch(FetchDescriptor<RouteStop>()) else { return }
        let byID = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for stop in stops where !stop.isCustomStop {
            if let client = byID[stop.clientID], follow(stop, client) { changed = true }
        }
        if changed { try? context.save() }
    }
}
