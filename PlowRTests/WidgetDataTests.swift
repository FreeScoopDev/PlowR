//
//  WidgetDataTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// What the home-screen widget is given, and what it says.
@MainActor
struct WidgetDataTests {

    private func progress(done: Int, of total: Int) -> RouteProgress {
        RouteProgress(routeID: UUID(), routeName: "Tuesday",
                      currentStopName: done < total ? "Client \(done)" : "All stops complete",
                      currentStopAddress: done < total ? "\(done) Main St" : "",
                      currentStopNumber: min(done + 1, total), totalStops: total, completedStops: done)
    }

    @Test func midRouteItShowsTheStopBeingWorked() {
        let data = SystemRouteSurfaces.widgetData(progress(done: 3, of: 8), isActive: true)
        #expect(data.stopLine == "Stop 4 of 8")
        #expect(data.nextStopName == "Client 3")
        #expect(data.nextStopAddress == "3 Main St")
    }

    // Every stop done, route not yet ended: it read "Stop 9 of 8", with
    // "All stops complete" as the next client.
    @Test func afterTheLastStopItSaysAllDone() {
        let data = SystemRouteSurfaces.widgetData(progress(done: 8, of: 8), isActive: true)
        #expect(data.stopLine == "All 8 stops done")
        #expect(data.nextStopName.isEmpty)
        #expect(data.progress == 1)
        #expect(!data.isComplete)
    }

    @Test func anEndedRouteIsComplete() {
        let data = SystemRouteSurfaces.widgetData(progress(done: 8, of: 8), isActive: false)
        #expect(data.isComplete)
        #expect(data.nextStopName.isEmpty)
    }

    @Test func aRouteWithNoStopsSaysSo() {
        #expect(TodayRouteWidgetData(isActive: true).stopLine == "No stops")
    }

    // The widget decodes the same type from the same suite and key.
    @Test func theWidgetReadsWhatTheAppWrites() {
        let written = SystemRouteSurfaces.widgetData(progress(done: 2, of: 5), isActive: true,
                                                     now: Date(timeIntervalSince1970: 1_800_000_000))
        WidgetDataStore.write(written)
        defer { WidgetDataStore.clear() }
        #expect(WidgetDataStore.read() == written)
    }
}
