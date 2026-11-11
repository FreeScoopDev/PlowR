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
/// the routes the client was already on. The place's Route Notes follow the
/// same way (`placeNotes`). The stop's own notes and what a run recorded are
/// the stop's and aren't touched, but for an exact copy of the place's
/// previous notes (`ownNote(_:following:to:)`). The client's upcoming visits
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
        // The address and pin are its place's: the client's own, or one of
        // their properties (Place). A missing place's stop keeps its own.
        guard let place = Place.of(client, propertyID: stop.propertyID) else { return changed }
        if stop.clientAddress != place.address { stop.clientAddress = place.address; changed = true }
        if stop.latitude != place.latitude { stop.latitude = place.latitude; changed = true }
        if stop.longitude != place.longitude { stop.longitude = place.longitude; changed = true }
        if stop.placeNotes != place.stopNotes {
            stop.stopNotes = ownNote(stop.stopNotes, following: stop.placeNotes, to: place.stopNotes)
            stop.placeNotes = place.stopNotes
            changed = true
        }
        return changed
    }

    /// A stop's own note when its place's notes change from `old` to `new`.
    /// Stops used to start with a copy of the place's notes as their own: a
    /// note that is exactly `old` (trimmed) was only ever that copy, and is
    /// cleared, or the old gate code would still show beside the new one.
    /// Any other note is the user's words and is kept. An `old` that's empty
    /// (a stop's first follow) clears nothing.
    nonisolated static func ownNote(_ own: String, following old: String, to new: String) -> String {
        let was = trimmed(old)
        guard !was.isEmpty, was != trimmed(new), trimmed(own) == was else { return own }
        return ""
    }

    /// The stop's own note as shown beside its place's notes: none when it
    /// says the same (a stop made before the notes followed the place).
    nonisolated static func shownOwnNote(_ own: String, placeNotes: String) -> String {
        trimmed(own) == trimmed(placeNotes) ? "" : own
    }

    nonisolated private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Duplicate Route: a new route, "<name> (Copy)", with `route`'s stops.
    /// A copy is a new route: inactive clients and properties, and places
    /// since removed, stay off it, as off every new route. A client's stop
    /// carries its own note only as the route shows it (`shownOwnNotes`): a
    /// note that is just a copy of the place's notes isn't carried, as the
    /// place's notes come with the place.
    @discardableResult
    static func duplicate(_ route: PlowRoute, clients: [Client], in context: ModelContext) -> PlowRoute {
        let copy = PlowRoute(name: "\(route.name) (Copy)", operatorID: route.operatorID)
        context.insert(copy)
        for (index, stop) in route.sortedStops.enumerated() {
            let stopCopy: RouteStop
            if stop.isCustomStop {
                stopCopy = RouteStop(order: index, customName: stop.clientName,
                                     customAddress: stop.clientAddress, customPhone: stop.clientPhone)
                stopCopy.stopNotes = stop.stopNotes
                stopCopy.propertyID = stop.propertyID
            } else if let client = clients.first(where: { $0.id == stop.clientID }), client.isActive,
                      let place = Place.of(client, propertyID: stop.propertyID), place.isActive {
                stopCopy = RouteStop(order: index, client: client, place: place)
                stopCopy.stopNotes = stop.shownOwnNotes
            } else {
                continue
            }
            stopCopy.equipmentNotes = stop.equipmentNotes
            stopCopy.targetMinutes = stop.targetMinutes
            stopCopy.expectedServiceIDs = stop.expectedServiceIDs
            stopCopy.hasOwnServices = stop.hasOwnServices
            stopCopy.route = copy
            context.insert(stopCopy)
        }
        return copy
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
        // Never making the poster wait (MainActorNotice).
        return center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { _ in
            MainActorNotice.run { sweep.schedule() }
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
                // A profile made on another device before this one's synced.
                BusinessProfiles.mergeDuplicates(in: container.mainContext)
                ServiceLog.linkEarlierVisits(in: container.mainContext)
                // Payments recorded on another device may now cover an invoice.
                Payments.settleAll(in: container.mainContext)
                // An invoice number two devices both gave out (InvoiceRecords).
                InvoiceRecords.resolveDuplicateNumbers(in: container.mainContext)
            }
        }
    }
}

extension RouteStop {
    /// This stop's own note as the route shows it (ClientStops.shownOwnNote).
    var shownOwnNotes: String { ClientStops.shownOwnNote(stopNotes, placeNotes: placeNotes) }

    /// Whether the route has a note to show for this stop: its place's, or its own.
    var hasNotesToShow: Bool {
        !placeNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !shownOwnNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
