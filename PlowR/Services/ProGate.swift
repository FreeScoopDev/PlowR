import Foundation

/// Why an action needs PlowR Pro, for the upgrade sheet. Each check asks
/// `Access` and returns nil when the action may go ahead, so a screen only
/// decides what to do next, never the rule.
enum ProGate: Identifiable, Equatable {
    /// The free tier's client limit.
    case clientLimit
    /// The free tier's one route, already made.
    case routeLimit
    /// On the free tier only the oldest route runs.
    case notFreeRoute(freeRoute: String)
    /// A Pro tool (Import Clients, the Request Link, …).
    case proFeature(String)
    /// Cancelled with more than the free tier's clients.
    case readOnly

    var id: String {
        switch self {
        case .clientLimit: "clientLimit"
        case .routeLimit: "routeLimit"
        case .notFreeRoute(let name): "notFreeRoute:\(name)"
        case .proFeature(let name): "proFeature:\(name)"
        case .readOnly: "readOnly"
        }
    }

    var title: String {
        switch self {
        case .clientLimit: "More Clients with PlowR Pro"
        case .routeLimit, .notFreeRoute: "More Routes with PlowR Pro"
        case .proFeature(let name): "\(name) Is Part of PlowR Pro"
        case .readOnly: "Your Subscription Ended"
        }
    }

    var message: String {
        let limit = Access.freeClientLimit
        return switch self {
        case .clientLimit:
            "The free tier keeps up to \(limit) active clients. PlowR Pro has no limit. Clients you mark inactive don't count."
        case .routeLimit:
            "The free tier has one route. PlowR Pro has as many as you need."
        case .notFreeRoute(let name):
            "The free tier runs one route, your first: \(name). PlowR Pro runs them all."
        case .proFeature:
            "PlowR Pro has every business tool, with unlimited clients and routes."
        case .readOnly:
            "Your records are all here: see them, export them and record payments. Subscribe again to add, change and run routes, right where you left off."
        }
    }

    // MARK: Checks

    /// Adding a client: one more counts against the free limit.
    static func addClient(_ access: Access) -> ProGate? {
        if access.canAddClient { return nil }
        return access.tier == .readOnly ? .readOnly : .clientLimit
    }

    /// Marking an inactive client active (by hand, or by booking them a
    /// visit): one more client.
    static func bringBack(_ client: Client, _ access: Access) -> ProGate? {
        Access.counts(client) ? nil : addClient(access)
    }

    static func createRoute(_ access: Access, routes: [PlowRoute], operatorID: String) -> ProGate? {
        if access.canCreateRoute(routes: routes, operatorID: operatorID) { return nil }
        return access.tier == .readOnly ? .readOnly : .routeLimit
    }

    static func startRoute(_ route: PlowRoute, access: Access, routes: [PlowRoute], operatorID: String) -> ProGate? {
        if access.canStartRoute(route, among: routes, operatorID: operatorID) { return nil }
        if access.tier == .readOnly { return .readOnly }
        let free = Access.freeRoute(in: routes, operatorID: operatorID)
        return .notFreeRoute(freeRoute: free?.name ?? "")
    }

    static func proFeature(_ name: String, _ access: Access) -> ProGate? {
        if access.canUseProFeatures { return nil }
        return access.tier == .readOnly ? .readOnly : .proFeature(name)
    }
}
