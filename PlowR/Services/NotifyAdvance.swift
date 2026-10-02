import Foundation

/// What the notify prompt's Send or Skip does to the route. After Done, it
/// completes the stop the screen showed. After Below Trigger, the stop was
/// already passed: the prompt is only the heads-up and completes nothing,
/// whatever iCloud does to the route meanwhile (a stop it completed, once
/// back in front, would be credited a visit it was marked as not needing).
enum NotifyAdvance {
    enum Outcome: Equatable {
        /// Moved on, by this or by Siri or Control Center meanwhile.
        case movedOn
        /// Nothing to complete: the heads-up after Below Trigger.
        case confirmed
        /// The stop changed on another device; nothing was recorded.
        case stopChanged
    }

    /// `completing`: the stop to complete, or nil for a heads-up only.
    static func run(completing stopID: UUID?, store: ActiveRouteStore) -> Outcome {
        guard let stopID else { return .confirmed }
        // Completed meanwhile by Siri or Control Center, with the notify sheet
        // up: done, not "changed on another device".
        if store.isBehindCurrentStop(stopID) { return .movedOn }
        return store.completeCurrentStop(expecting: stopID) == .stopChanged ? .stopChanged : .movedOn
    }
}
