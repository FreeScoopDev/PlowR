import Foundation

/// What Siri and Control Center hand the route screen. Completing a stop
/// doesn't come through here: it goes through ActiveRouteStore
/// (CompleteStopAction), with or without the route screen.
@Observable
final class RouteSessionManager {
    static let shared = RouteSessionManager()
    private init() {}

    /// Siri's "Notify next client": the stop whose client to text, and when
    /// Siri asked. The route screen opens the text when it can and clears
    /// this (NotifyNextAction.stopToOpen decides whether it still should).
    var textRequest: NotifyNextAction.Request?
    /// Why Control Center's Complete Stop didn't complete the stop (the
    /// route changed on another device, say). The route screen shows it.
    var completeStopMessage: String?
}
