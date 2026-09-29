//
//  RouteRunSummaryTests.swift
//  PlowRTests
//

import Testing
@testable import PlowR

/// How a route reads in the route list and on the dashboard.
@MainActor
struct RouteRunSummaryTests {

    private func stops(done: Int, of total: Int) -> [RouteStop] {
        (0..<total).map { i in
            let stop = RouteStop(order: i, customName: "Stop \(i)")
            stop.actualMinutes = i < done ? 5 : 0
            return stop
        }
    }

    // Worked out from the counts, a route ended part-way stayed orange
    // "in progress" for good. Only the route store knows it's running.
    @Test func aRouteEndedPartWayIsNotRunning() {
        let run = RouteRunSummary(stops: stops(done: 2, of: 5), isRunning: false)
        #expect(!run.isRunning)
        #expect(!run.isDone)
        #expect(run.done == 2)
    }

    @Test func aRunningRouteIsRunning() {
        #expect(RouteRunSummary(stops: stops(done: 2, of: 5), isRunning: true).isRunning)
    }

    // Every stop done but not yet ended: still running, not "Completed".
    @Test func completedOnlyOnceTheRouteHasEnded() {
        #expect(!RouteRunSummary(stops: stops(done: 5, of: 5), isRunning: true).isDone)
        #expect(RouteRunSummary(stops: stops(done: 5, of: 5), isRunning: false).isDone)
        #expect(!RouteRunSummary(stops: [], isRunning: false).isDone)
    }
}
