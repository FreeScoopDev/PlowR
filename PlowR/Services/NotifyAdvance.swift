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
    /// `recording`: the services the "Done:" button named, recorded only if
    /// this completes the stop (OneTapServices). Cancel never gets here.
    static func run(completing stopID: UUID?, recording services: [String] = [],
                    store: ActiveRouteStore) -> Outcome {
        guard let stopID else { return .confirmed }
        // Completed meanwhile by Siri or Control Center, with the notify sheet
        // up: done, not "changed on another device".
        if store.isBehindCurrentStop(stopID) { return .movedOn }
        return store.completeCurrentStop(expecting: stopID, recordingServices: services) == .stopChanged ? .stopChanged : .movedOn
    }

    /// Which stop, and which services, a completion from the route screen
    /// completes: the stop drawn on the card when the button was tapped
    /// (never the store's current stop read later, which iCloud may have
    /// moved on to another client), with the services that button named.
    /// The text sheet holds one while it's open; every way of opening it
    /// makes a new one, so nothing carries over from a sheet cancelled
    /// before, and Cancel drops it (`cancelled()`).
    struct Completion: Equatable {
        /// The stop to complete; nil completes nothing (the heads-up).
        private(set) var stopID: UUID?
        /// What the "Done:" button named; empty for any other way in.
        private(set) var serviceIDs: [String]

        /// Nothing to complete: no sheet open, or one cancelled.
        static let nothing = Completion(stopID: nil, serviceIDs: [])

        /// The copper button or Complete Without Services, tapped on the
        /// card showing `drawnStop`, naming `services` (empty for any but "Done:").
        static func button(drawnStop: UUID, recording services: [String]) -> Completion {
            Completion(stopID: drawnStop, serviceIDs: services)
        }

        /// The text offered after leaving the current stop's area: no
        /// button named any services, so none are recorded.
        static func exitOffer(currentStop: UUID?) -> Completion {
            Completion(stopID: currentStop, serviceIDs: [])
        }

        /// The heads-up after Below Trigger: the stop was already passed.
        static let headsUp = nothing

        /// Cancel: the sheet closes and completes nothing.
        func cancelled() -> Completion { .nothing }

        /// Send or Skip.
        func run(store: ActiveRouteStore) -> Outcome {
            NotifyAdvance.run(completing: stopID, recording: serviceIDs, store: store)
        }
    }
}
