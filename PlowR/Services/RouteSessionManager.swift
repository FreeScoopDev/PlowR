import Foundation

/// Shared state that bridges Siri's Notify Next Client to the route view, which
/// registers it on appear and clears it on disappear. Completing a stop doesn't
/// come through here any more: it goes through ActiveRouteStore
/// (CompleteStopAction), with or without the route screen.
@Observable
final class RouteSessionManager {
    static let shared = RouteSessionManager()
    private init() {}

    var isRouteActive = false

    var onNotifyNext: (() -> Void)?
}
