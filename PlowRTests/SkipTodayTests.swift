//
//  SkipTodayTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Stops left out of a run (Skip Today, Start From Here) stay on the route,
/// and the run goes as if they weren't there: its stops, numbers, progress,
/// completions, and after a relaunch.
@MainActor
struct SkipTodayTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    @Test func aSkippedFirstStopStartsTheRunAtTheNext() throws {
        let h = try Harness(stopCount: 3)
        let stops = h.route.sortedStops
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route, skipping: [stops[0].id])
        #expect(store.currentStop?.id == stops[1].id)
        #expect(store.sortedStops.map(\.id) == [stops[1].id, stops[2].id])
        #expect(surfaces.last?.totalStops == 2)
        #expect(surfaces.last?.currentStopNumber == 1)
        // Still on the route.
        #expect(h.route.sortedStops.count == 3)
    }

    @Test func completingGoesPastASkippedStop() throws {
        let h = try Harness(stopCount: 3)
        let stops = h.route.sortedStops
        let store = h.makeStore()
        store.start(h.route, skipping: [stops[1].id])
        store.completeShownStop()
        #expect(store.currentStop?.id == stops[2].id)
        store.completeShownStop()
        #expect(store.allStopsDone)
        #expect(stops[1].actualMinutes == 0)
    }

    // Start From Here is the stops before it, left out.
    @Test func startingPartwayLeavesTheEarlierStopsOut() throws {
        let h = try Harness(stopCount: 3)
        let stops = h.route.sortedStops
        let store = h.makeStore()
        store.start(h.route, skipping: Set(stops.prefix(2).map(\.id)))
        #expect(store.currentStop?.id == stops[2].id)
        #expect(store.isLastStop)
    }

    // A skipped stop isn't the current one: a completion naming it (as a
    // stale screen would) records nothing.
    @Test func aSkippedStopCantBeCompleted() throws {
        let h = try Harness(stopCount: 2)
        let stops = h.route.sortedStops
        let store = h.makeStore()
        store.start(h.route, skipping: [stops[0].id])
        #expect(store.completeCurrentStop(expecting: stops[0].id) == .stopChanged)
    }

    @Test func aRelaunchKeepsTheStopsLeftOut() throws {
        let h = try Harness(stopCount: 3)
        let stops = h.route.sortedStops
        let before = h.makeClosedAppStore()
        before.start(h.route, skipping: [stops[0].id])
        let after = h.makeStore()
        #expect(after.skippedStopIDs == [stops[0].id])
        #expect(after.currentStop?.id == stops[1].id)
    }

    // A checkpoint saved before this existed: nothing left out.
    @Test func aCheckpointFromBeforeLeavesNothingOut() throws {
        let h = try Harness(stopCount: 2)
        let old = ActiveRouteStore.Checkpoint(routeID: h.route.id, currentStopIndex: 1,
                                              currentStopID: h.route.sortedStops[1].id, stopStartedAt: h.clock,
                                              stopChangedUnseen: nil, runID: UUID(), runStartedAt: h.clock,
                                              skippedStopIDs: nil)
        let data = try JSONEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("skippedStopIDs"))
        h.defaults.set(data, forKey: ActiveRouteStore.checkpointKey)
        let store = h.makeStore()
        #expect(store.skippedStopIDs.isEmpty)
        #expect(store.currentStop?.id == h.route.sortedStops[1].id)
    }

    @Test func endingTheRunForgetsTheStopsLeftOut() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route, skipping: [h.route.sortedStops[0].id])
        store.end()
        #expect(store.skippedStopIDs.isEmpty)
        store.start(h.route)
        #expect(store.sortedStops.count == 2)
    }
}
