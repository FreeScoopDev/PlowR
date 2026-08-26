import Foundation

/// Shared state that bridges AppIntents (Siri) to the currently active route view.
/// ActiveRouteView registers closures on appear and clears them on disappear.
@Observable
final class RouteSessionManager {
    static let shared = RouteSessionManager()
    private init() {}

    var isRouteActive = false
    var onCompleteStop: (() -> Void)?
    var onNotifyNext: (() -> Void)?
}
