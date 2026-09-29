//
//  CompleteStopActionTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// Siri's "Complete current stop" and Control Center's Complete Stop. Siri
/// reached the stop only through the route screen while it showed, opened
/// the notify prompt instead of completing, and said "Stop marked complete."
/// whatever happened. Control Center only opened the app.
@MainActor
struct CompleteStopActionTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    @Test func withNoRouteItSaysSo() throws {
        let h = try Harness()
        let store = h.makeStore()
        #expect(CompleteStopAction.run(in: store) == "No route is in progress.")
    }

    @Test func itCompletesTheStopAndSaysWhichIsNext() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        h.clock = h.clock.addingTimeInterval(12 * 60)
        #expect(CompleteStopAction.run(in: store) == "Client 0 is done. Next: Client 1.")
        #expect(store.currentStopIndex == 1)
        // Recorded like a completion on the route screen: the visit's time.
        #expect(h.route.sortedStops[0].actualMinutes == 12)
    }

    @Test func theLastStopSaysTheRouteIsDone() throws {
        let h = try Harness(stopCount: 1)
        let store = h.makeStore()
        store.start(h.route)
        #expect(CompleteStopAction.run(in: store) == "Client 0 is done. That was the last stop on the route.")
        #expect(store.currentStop == nil)
        // Asked again: nothing more to complete, and nothing recorded twice.
        #expect(CompleteStopAction.run(in: store) == "Every stop on this route is already done.")
    }

    // Deleted on another device while the app was away: the store notices,
    // ends the route, and nothing is credited to anyone.
    @Test func aRouteDeletedElsewhereIsNotCompleted() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        h.context.delete(h.route)
        try h.context.save()
        #expect(CompleteStopAction.run(in: store) == "No route is in progress.")
    }

    @Test func theControlCentersLinkIsTheOneTheAppHandles() {
        #expect(CompleteStopAction.link?.scheme == "plowr")
        #expect(CompleteStopAction.link?.host == "completeStop")
    }
}
