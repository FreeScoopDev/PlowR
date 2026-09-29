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

    /// What Siri does, for a business.
    private func siri(_ store: ActiveRouteStore) -> CompleteStopAction.Reply {
        CompleteStopAction.siri(in: store, role: UserRole.business)
    }

    /// What Control Center's intent does in the app, for a business, with
    /// the stop its control showed: what the route screen says, if anything.
    private func controlCenter(_ store: ActiveRouteStore, stop: UUID) -> String? {
        CompleteStopAction.controlCenter(stopID: stop, in: store, role: UserRole.business)
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
    // on since (a second tap), nothing more is completed, and the route screen
    // says that stop is done, not that the route changed.
    @Test func aStopThatIsntCurrentAnyMoreIsntCompleted() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let shown = try #require(store.currentStopID)
        #expect(controlCenter(store, stop: shown) == nil)            // completed: nothing to say
        #expect(controlCenter(store, stop: shown) == "Client 0 is already done.")
        #expect(store.currentStopIndex == 1)
        #expect(h.clients[0].totalVisits == 1)
        #expect(h.clients[1].totalVisits == 0)
    }

    // A stop the widget showed that the route no longer has (removed on
    // another device, and the route screen has since shown the new stop).
    @Test func aStopTheRouteNoLongerHasIsntCompleted() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let shown = try #require(store.currentStopID)
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        store.validate()
        store.markCurrentStopSeen()
        #expect(controlCenter(store, stop: shown)?.contains("changed on another device") == true)
        #expect(h.clients.allSatisfy { $0.totalVisits == 0 })
    }

    // Only a business runs routes: in client mode, or before a role is
    // chosen, neither Siri nor Control Center completes anything.
    @Test func onlyABusinessCompletesStops() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let shown = try #require(store.currentStopID)
        for role in ["client", "", nil] as [String?] {
            #expect(CompleteStopAction.siri(in: store, role: role) == .init(text: "No route is in progress.",
                                                                          completed: false))
            #expect(CompleteStopAction.controlCenter(stopID: shown, in: store, role: role) == nil)
        }
        #expect(store.currentStopIndex == 0)
        #expect(h.clients.allSatisfy { $0.totalVisits == 0 })
    }

    // What a business's device has stored since the first version. Siri
    // and Control Center check it, and a new value would lock them out.
    @Test func theBusinessRoleIsWhatDevicesHaveStored() {
        #expect(UserRole.key == "userRole")
        #expect(UserRole.business == "operator")
    }

    // With no route in progress there's no route screen to say anything on
    // (it would pop up on the next route).
    @Test func withNoRouteControlCenterSaysNothing() throws {
        let h = try Harness()
        let store = h.makeStore()
        #expect(controlCenter(store, stop: UUID()) == nil)
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

    // iCloud moves the route on while PlowR is in the background, and iOS
    // then ends it. After the relaunch the new stop is still unseen: the
    // checkpoint already points at it, so the relaunch alone can't tell.
    @Test func anUnseenStopStaysUnseenAfterTheAppIsEnded() throws {
        let h = try Harness()
        let running = h.makeStore()
        running.start(h.route)
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        running.validate()
        #expect(running.stopChangedUnseen)
        let relaunched = h.makeStore()
        #expect(relaunched.stopChangedUnseen)
        #expect(!siri(relaunched).completed)
        #expect(h.clients[1].totalVisits == 0)
        // Seen after the relaunch, and that's kept too.
        relaunched.markCurrentStopSeen()
        #expect(!h.makeStore().stopChangedUnseen)
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
    @Test func theRouteLinkRoundTrips() throws {
        #expect(PlowRLink(try #require(PlowRLink.activeRoute.url)) == .activeRoute)
        #expect(PlowRLink.activeRoute.url?.absoluteString == "plowr://activeRoute")
    }

    // Control Center completes through its intent in the app, not a link:
    // a link from anywhere could otherwise complete a stop.
    @Test func otherLinksArentPlowRs() throws {
        #expect(PlowRLink(try #require(URL(string: "https://example.com/activeRoute"))) == nil)
        #expect(PlowRLink(try #require(URL(string: "plowr://completeStop?stop=\(UUID().uuidString)"))) == nil)
        #expect(PlowRLink(try #require(URL(string: "plowr://somewhereElse"))) == nil)
    }

    // Control Center's intent carries the stop its control showed, not the
    // one the app has moved to by the time the intent runs in it.
    @Test func controlCentersIntentCarriesTheStopItShowed() {
        let stop = UUID()
        #expect(CompleteStopControlIntent(stopID: stop).stopID == stop.uuidString)
        #expect(CompleteStopControlIntent(stopID: nil).stopID == nil)
    }

    // The stop Control Center's button shows and completes: the one the
    // widget shows, while a route is in progress.
    @Test func controlCenterCompletesTheStopTheWidgetShows() {
        let stop = UUID()
        var data = TodayRouteWidgetData(routeName: "Tuesday", totalStops: 3, completedStops: 1,
                                        nextStopName: "B", nextStopAddress: "", isActive: true,
                                        lastUpdated: .now, currentStopID: stop)
        #expect(data.shownStopID == stop)
        data.isActive = false
        #expect(data.shownStopID == nil)
        data.isActive = true
        data.currentStopID = nil
        #expect(data.shownStopID == nil)
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
