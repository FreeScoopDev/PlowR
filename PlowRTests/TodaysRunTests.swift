//
//  TodaysRunTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// The run about to start from a route's page: its stops, the Start title,
/// and what Start From Here leaves out.
struct TodaysRunTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test func todaysStopsLeaveOutTheSkipped() {
        var run = TodaysRun(routeStops: [a, b, c, d])
        #expect(run.startTitle == "Start Route")
        run.toggle(b)
        #expect(run.stops == [a, c, d])
        #expect(!run.isIncluded(b) && run.isIncluded(a))
        #expect(run.startTitle == "Start Route · 3 of 4 Stops")
        run.toggle(b)
        #expect(run.stops == [a, b, c, d])
    }

    // Start From Here at the third stop leaves out the first two, and any
    // skipped after it; never the chosen stop itself.
    @Test func startingFromAStopLeavesOutTheOnesBefore() {
        var run = TodaysRun(routeStops: [a, b, c, d])
        #expect(run.skipping(from: 2) == [a, b])
        #expect(run.skipping(from: 0) == [])
        run.toggle(d)
        #expect(run.skipping(from: 2) == [a, b, d])
    }

    // A skipped stop since removed from the route doesn't count.
    @Test func aSkippedStopNoLongerOnTheRouteIsIgnored() {
        let run = TodaysRun(routeStops: [a, b], skipped: [c])
        #expect(run.skippedOnRoute.isEmpty)
        #expect(run.startTitle == "Start Route")
        #expect(run.stops == [a, b])
    }
}
