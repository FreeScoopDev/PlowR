import Foundation

/// Completing the stop you're at from outside the route screen: Siri's
/// "Complete current stop" and Control Center's Complete Stop. Both go
/// through ActiveRouteStore, like the screen, so they work whether or not the
/// route screen is open, and a visit is never credited to a client who wasn't
/// visited.
///
/// Siri used to reach the stop only through the route screen, while it was
/// showing: it opened the notify prompt instead of completing, did nothing on
/// the last stop, and said "Stop marked complete." either way. Control Center
/// only opened the app.
enum CompleteStopAction {
    struct Reply: Equatable {
        var text: String
        /// A stop was completed. Otherwise the text says why not.
        var completed: Bool
    }

    /// Completes the current stop if it's `stopID`, the one the caller saw
    /// (Siri: the store's current stop; Control Center: the one the widget
    /// showed), and says what happened, for Siri to read out.
    static func run(in store: ActiveRouteStore, expecting stopID: UUID?) -> Reply {
        store.validate()
        guard store.isActive else { return Reply(text: "No route is in progress.", completed: false) }
        // Moved on another device since the user last looked: completing now
        // would credit whoever is current, maybe not the client they're at.
        guard !store.stopChangedUnseen else { return changed }
        guard let stopID, let stop = store.currentStop else {
            return Reply(text: "Every stop on this route is already done.", completed: false)
        }
        let done = stop.clientName.isEmpty ? "That stop" : stop.clientName
        switch store.completeCurrentStop(expecting: stopID) {
        case .advanced:
            let next = store.currentStop?.clientName ?? ""
            return Reply(text: next.isEmpty ? "\(done) is done." : "\(done) is done. Next: \(next).", completed: true)
        case .finishedLastStop:
            return Reply(text: "\(done) is done. That was the last stop: end the route in PlowR when you're ready.",
                         completed: true)
        case .allStopsAlreadyDone:
            return Reply(text: "Every stop on this route is already done.", completed: false)
        case .noActiveRoute:
            return Reply(text: "No route is in progress.", completed: false)
        case .stopChanged:
            return changed
        }
    }

    private static let changed = Reply(
        text: "The route changed on another device, so no stop was marked complete. Open PlowR to see the stop you're at.",
        completed: false)
}
