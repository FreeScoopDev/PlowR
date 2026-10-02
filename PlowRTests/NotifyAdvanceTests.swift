import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The notify prompt's Send or Skip: after Done it completes the stop shown;
/// after Below Trigger it's a heads-up and completes nothing.
@MainActor
struct NotifyAdvanceTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    @Test func theHeadsUpAfterBelowTriggerCompletesNothingEvenIfThePassedStopComesBack() throws {
        let h = try Harness(stopCount: 4)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops                     // A, B, C, D
        store.passCurrentStop(expecting: stops[0].id)       // Below Trigger at A; B is current
        // On another device: B comes off the route and A is moved into its place.
        stops[0].order = 1
        stops[2].order = 0
        h.context.delete(stops[1])
        try h.context.save()
        #expect(store.currentStopID == stops[0].id)         // A is current again
        #expect(NotifyAdvance.run(completing: nil, store: store) == .confirmed)
        #expect(store.currentStopID == stops[0].id)
        #expect(h.clients[0].totalVisits == 0)
        #expect(try h.context.fetch(FetchDescriptor<ServiceRecord>()).isEmpty)
    }

    @Test func afterDoneItCompletesTheStopShownOrSaysWhatHappened() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        #expect(NotifyAdvance.run(completing: stops[0].id, store: store) == .movedOn)
        #expect(h.clients[0].totalVisits == 1)
        // Already completed meanwhile (Siri, Control Center): moved on, nothing more.
        #expect(NotifyAdvance.run(completing: stops[0].id, store: store) == .movedOn)
        #expect(h.clients[0].totalVisits == 1)
        // A stop no longer current (changed on another device): nothing recorded.
        #expect(NotifyAdvance.run(completing: stops[2].id, store: store) == .stopChanged)
        #expect(h.clients[2].totalVisits == 0)
    }
}
