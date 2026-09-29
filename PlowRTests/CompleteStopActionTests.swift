//
//  CompleteStopActionTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Siri's "Complete current stop" and Control Center's Complete Stop. Siri
/// reached the stop only through the route screen while it showed, opened
/// the notify prompt instead of completing, and said "Stop marked complete."
/// whatever happened. Control Center only opened the app.
@MainActor
struct CompleteStopActionTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    /// What Siri does: the store's current stop.
    private func siri(_ store: ActiveRouteStore) -> CompleteStopAction.Reply {
        CompleteStopAction.run(in: store, expecting: store.currentStopID)
    }

    @Test func withNoRouteItSaysSo() throws {
        let h = try Harness()
        let store = h.makeStore()
        #expect(siri(store) == .init(text: "No route is in progress.", completed: false))
    }

    @Test func itCompletesTheStopAndSaysWhichIsNext() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        h.clock = h.clock.addingTimeInterval(12 * 60)
        #expect(siri(store) == .init(text: "Client 0 is done. Next: Client 1.", completed: true))
        #expect(store.currentStopIndex == 1)
        // Recorded like a completion on the route screen.
        #expect(h.route.sortedStops[0].actualMinutes == 12)
        #expect(h.clients[0].totalVisits == 1)
    }

    // Siri runs with the app in the background, which can be suspended
    // before autosave: the completion is saved at once.
    @Test func theCompletionIsSavedAtOnce() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        try h.context.save()
        #expect(siri(store).completed)
        #expect(!h.context.hasChanges)
    }

    @Test func theLastStopSaysSoAndNothingIsRecordedTwice() throws {
        let h = try Harness(stopCount: 1)
        let store = h.makeStore()
        store.start(h.route)
        #expect(siri(store).text == "Client 0 is done. That was the last stop: end the route in PlowR when you're ready.")
        #expect(siri(store) == .init(text: "Every stop on this route is already done.", completed: false))
        #expect(h.clients[0].totalVisits == 1)
    }

    // Control Center names the stop its widget showed. If the route has moved
    // on since (a second tap), nothing more is completed.
    @Test func aStopThatIsntCurrentAnyMoreIsntCompleted() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let shown = try #require(store.currentStopID)
        #expect(CompleteStopAction.run(in: store, expecting: shown).completed)
        #expect(!CompleteStopAction.run(in: store, expecting: shown).completed)
        #expect(store.currentStopIndex == 1)
        #expect(h.clients[1].totalVisits == 0)
    }

    // The office removes the stop the driver is at while the app is closed.
    // The next launch moves the route to the next stop, which the driver
    // hasn't seen: completing then would credit that client with a visit.
    @Test func aStopTheRouteMovedToUnseenIsntCompleted() throws {
        let h = try Harness()
        let before = h.makeClosedAppStore()
        before.start(h.route)
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        let store = h.makeStore()                   // the relaunch
        #expect(store.isActive)
        #expect(store.stopChangedUnseen)
        let reply = siri(store)
        #expect(!reply.completed)
        #expect(reply.text.contains("changed on another device"))
        #expect(h.clients[1].totalVisits == 0)
        // Once the route screen has shown it, it can be completed.
        store.markCurrentStopSeen()
        #expect(siri(store).completed)
        #expect(h.clients[1].totalVisits == 1)
    }

    // The same while the app is running: iCloud removes the current stop.
    @Test func aStopRemovedWhileRunningIsntCompletedUntilSeen() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        store.validate()
        #expect(store.stopChangedUnseen)
        #expect(!siri(store).completed)
        #expect(h.clients[1].totalVisits == 0)
    }

    @Test func aRouteDeletedWhileClosedIsNotCompleted() throws {
        let h = try Harness()
        let before = h.makeClosedAppStore()
        before.start(h.route)
        h.context.delete(h.route)
        try h.context.save()
        let store = h.makeStore()
        #expect(siri(store) == .init(text: "No route is in progress.", completed: false))
        #expect(h.clients.allSatisfy { $0.totalVisits == 0 })
    }

    // The route screen's notify sheet can outlive its stop being completed by
    // Siri; that stop is behind the current one, not "changed".
    @Test func aStopCompletedThisRunIsBehindTheCurrentOne() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        #expect(!store.isBehindCurrentStop(first))
        _ = siri(store)
        #expect(store.isBehindCurrentStop(first))
        #expect(!store.isBehindCurrentStop(try #require(store.currentStopID)))
        #expect(!store.isBehindCurrentStop(UUID()))
    }
}

/// PlowR's links, shared by the app and the widget extension.
struct PlowRLinkTests {
    @Test func linksRoundTrip() throws {
        for link in [PlowRLink.activeRoute, .completeStop(UUID())] {
            #expect(PlowRLink(try #require(link.url)) == link)
        }
        #expect(PlowRLink.activeRoute.url?.absoluteString == "plowr://activeRoute")
    }

    @Test func otherLinksArentPlowRs() throws {
        #expect(PlowRLink(try #require(URL(string: "https://example.com/completeStop"))) == nil)
        #expect(PlowRLink(try #require(URL(string: "plowr://completeStop"))) == nil)       // no stop named
        #expect(PlowRLink(try #require(URL(string: "plowr://completeStop?stop=nope"))) == nil)
        #expect(PlowRLink(try #require(URL(string: "plowr://somewhereElse"))) == nil)
    }

    // What Control Center's button opens, from what the widget shows.
    @Test func controlCenterNamesTheStopTheWidgetShows() {
        let stop = UUID()
        var data = TodayRouteWidgetData(routeName: "Tuesday", totalStops: 3, completedStops: 1,
                                        nextStopName: "B", nextStopAddress: "", isActive: true,
                                        lastUpdated: .now, currentStopID: stop)
        #expect(PlowRLink.completeStopControl(showing: data) == .completeStop(stop))
        data.currentStopID = nil
        #expect(PlowRLink.completeStopControl(showing: data) == .activeRoute)
        data.currentStopID = stop
        data.isActive = false
        #expect(PlowRLink.completeStopControl(showing: data) == .activeRoute)
        #expect(PlowRLink.completeStopControl(showing: nil) == .activeRoute)
    }

    // The app writes the stop it shows for the widget, and none once every
    // stop is done.
    @Test func theWidgetIsGivenTheStopItShows() {
        let stop = UUID()
        let working = RouteProgress(routeID: UUID(), routeName: "Tuesday", currentStopName: "B",
                                    currentStopAddress: "", currentStopNumber: 2, totalStops: 3,
                                    completedStops: 1, currentStopID: stop)
        #expect(SystemRouteSurfaces.widgetData(working, isActive: true).currentStopID == stop)
        var done = working
        done.completedStops = 3
        #expect(SystemRouteSurfaces.widgetData(done, isActive: true).currentStopID == nil)
    }
}
