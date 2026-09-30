import Foundation
import SwiftData

/// The services a route stop is expected to need. A stop follows its client's
/// usual services until it's given a list of its own on its route: a client
/// can need clearing on the storm route and salting on the ice route. A
/// custom stop (no client) only has its own.
///
/// Changing a stop's services asks where the change applies (Joe's call):
/// only this route, or the client's usual services, which every route's stop
/// for them then follows, including stops that had their own list.
enum StopServices {
    /// The service IDs `stop` is expected to need.
    static func expected(for stop: RouteStop, client: Client?) -> [String] {
        if stop.hasOwnServices { return stop.expectedServiceIDs }
        return client?.expectedServiceIDs ?? []
    }

    /// `ids` for `stop`, where the user chose: its client's usual services on
    /// every route, or this route only. A custom stop has no client: this
    /// route only. Unchanged from what the page opened with (`openedWith`):
    /// nothing happens, so saving only a note can't detach the stop from its
    /// client's services.
    static func apply(_ ids: [String], to stop: RouteStop, client: Client?, allRoutes: Bool,
                      openedWith: Set<String>? = nil, in context: ModelContext) {
        if let openedWith, Set(ids) == openedWith { return }
        if allRoutes, let client {
            setForAllRoutes(ids, for: client, in: context)
        } else {
            setForThisRoute(ids, on: stop)
        }
    }

    /// `ids` for `stop` on its route only.
    static func setForThisRoute(_ ids: [String], on stop: RouteStop) {
        stop.expectedServiceIDs = ids
        stop.hasOwnServices = true
    }

    /// `ids` as `client`'s usual services, and every route's stop for them
    /// following them again.
    static func setForAllRoutes(_ ids: [String], for client: Client, in context: ModelContext) {
        client.expectedServiceIDs = ids
        for stop in (try? ClientStops.of(client, in: context)) ?? [] {
            stop.hasOwnServices = false
            stop.expectedServiceIDs = []
        }
    }
}

extension RouteStop {
    /// Driving directions to the stop in Apple Maps: to its pin, or its
    /// address if it has none. The route screen and a stop's page both use it.
    var appleMapsDirectionsURL: URL? {
        if latitude != 0 {
            return URL(string: "maps://?daddr=\(latitude),\(longitude)&dirflg=d")
        }
        let address = clientAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return address.isEmpty ? nil : URL(string: "maps://?daddr=\(address)")
    }
}
