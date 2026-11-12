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
        /// What the "Done:" button named, or the exit offer's sentence
        /// named; empty for any other way in.
        private(set) var serviceIDs: [String]
        /// What the sheet says Send or Skip does, above its buttons: only
        /// the exit offer has one (`OneTapServices.exitOfferNotice`). Opened
        /// from a button, the button already said it.
        private(set) var notice: String?
        /// The exit offer's: the names of `serviceIDs`, in the same order,
        /// and the stop's client, for saying afterwards what wasn't recorded.
        private(set) var serviceNames: [String] = []
        private(set) var clientName = ""

        /// Whether Send or the other button completes a stop.
        var completesStop: Bool { stopID != nil }

        /// The sheet's button that doesn't text: it completes the stop, or
        /// (the heads-up, a text only) nothing. Never "Skip": that read as
        /// skipping the stop.
        var skipLabel: String { completesStop ? "Complete Without Text" : "No Text" }

        /// Nothing to complete: no sheet open, or one cancelled.
        static let nothing = Completion(stopID: nil, serviceIDs: [])

        /// The copper button or Complete Without Services, tapped on the
        /// card showing `drawnStop`, naming `services` (empty for any but "Done:").
        static func button(drawnStop: UUID, recording services: [String]) -> Completion {
            Completion(stopID: drawnStop, serviceIDs: services)
        }

        /// The text offered after leaving the current stop's area, for
        /// `leftStop` (the exit's stop, checked to be the current one), with
        /// `main` the copper button the card has for it now. Send or Skip
        /// records what that button would ("Done:" names services; any other
        /// records nothing new), and the sheet says so, naming every service
        /// (Joe, 2026-11-10). Names and IDs come from the same button, so it
        /// never records one it didn't name or names one it won't record;
        /// the store's re-check still records nothing if something was
        /// recorded meanwhile.
        static func exitOffer(leftStop: UUID, clientName: String, main: OneTapServices.MainButton) -> Completion {
            var names: [String] = []
            if case .done(_, let named) = main { names = named }
            return Completion(stopID: leftStop, serviceIDs: main.recordedServiceIDs,
                              notice: OneTapServices.exitOfferNotice(clientName: clientName, names: names),
                              serviceNames: names, clientName: clientName)
        }

        /// The heads-up after Below Trigger: the stop was already passed.
        static let headsUp = nothing

        /// Cancel: the sheet closes and completes nothing.
        func cancelled() -> Completion { .nothing }

        /// Send or Skip.
        func run(store: ActiveRouteStore) -> Outcome {
            NotifyAdvance.run(completing: stopID, recording: serviceIDs, store: store)
        }

        /// Send or Skip, and the names of the services the sheet named that
        /// this didn't record: the store's re-check found something recorded
        /// or invoiced meanwhile, a named service left the catalog, a named
        /// per-square-foot service lost its price because the place's
        /// measured area was removed (`OneTapServices.stillPriced`), or Siri
        /// or Control Center completed the stop first. Empty when all were
        /// recorded, when none were named (a button's sheet says nothing,
        /// the button did), and on `.stopChanged`, which the screen already
        /// reports. It goes by what is on the stop afterwards, whoever put it
        /// there: a service Record Services saved while the sheet was up is
        /// recorded, and saying it wasn't would be untrue.
        @MainActor
        func runNotingUnrecorded(store: ActiveRouteStore) -> (outcome: Outcome, notRecorded: [String]) {
            let stop = stopID.flatMap { id in store.sortedStops.first { $0.id == id } }
            let outcome = run(store: store)
            guard notice != nil, !serviceIDs.isEmpty, outcome != .stopChanged else { return (outcome, []) }
            let onStop = stop?.completedServiceIDs ?? []
            return (outcome, Self.notRecorded(ids: serviceIDs, names: serviceNames, recorded: onStop))
        }

        /// The names, of the services named (`ids`, `names` in step), that
        /// aren't among those `recorded` on the stop.
        static func notRecorded(ids: [String], names: [String], recorded: [String]) -> [String] {
            zip(ids, names).filter { !recorded.contains($0.0) }.map(\.1)
        }
    }
}
