import Foundation

/// Completing the stop you're at from outside the route screen: Siri's
/// "Complete current stop" and Control Center's Complete Stop. Both go
/// through ActiveRouteStore, like the screen, so they work whether or not the
/// route screen is open.
///
/// Siri used to reach the stop only through the route screen, while it was
/// showing: it opened the notify prompt instead of completing, did nothing on
/// the last stop, and said "Stop marked complete." either way. Control Center
/// only opened the app.
enum CompleteStopAction {
    /// The link Control Center's button opens (`ContentView` handles it).
    static let link = URL(string: "plowr://completeStop")

    /// Completes the current stop and says what happened, for Siri to read out.
    static func run(in store: ActiveRouteStore) -> String {
        store.validate()
        guard store.isActive else { return "No route is in progress." }
        guard let stop = store.currentStop else { return "Every stop on this route is already done." }
        let done = stop.clientName.isEmpty ? "That stop" : stop.clientName
        switch store.completeCurrentStop(expecting: stop.id) {
        case .advanced:
            let next = store.currentStop?.clientName ?? ""
            return next.isEmpty ? "\(done) is done." : "\(done) is done. Next: \(next)."
        case .finishedLastStop:
            return "\(done) is done. That was the last stop on the route."
        case .allStopsAlreadyDone:
            return "Every stop on this route is already done."
        case .noActiveRoute:
            return "No route is in progress."
        case .stopChanged:
            return "The route changed on another device. Open PlowR to see the stop you're at."
        }
    }
}
