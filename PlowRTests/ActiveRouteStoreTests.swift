//
//  ActiveRouteStoreTests.swift
//  PlowRTests
//

import Testing
import Foundation
import SwiftData
@testable import PlowR

/// Records what the store asked the Live Activity / widget to do.
final class FakeRouteSurfaces: RouteSurfaces {
    var calls: [String] = []
    var last: RouteProgress?
    func start(_ p: RouteProgress) { calls.append("start"); last = p }
    func update(_ p: RouteProgress) { calls.append("update"); last = p }
    func resume(_ p: RouteProgress) { calls.append("resume"); last = p }
    func end(_ p: RouteProgress) { calls.append("end"); last = p }
    func clear() { calls.append("clear") }
}

@MainActor
struct ActiveRouteStoreTests {

    /// An in-memory SwiftData store, a private UserDefaults and a clock the test controls.
    @MainActor
    final class Harness {
        let container: ModelContainer
        let context: ModelContext
        let defaults: UserDefaults
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let client: Client
        let route: PlowRoute

        init(stopCount: Int = 3) throws {
            container = try ModelContainer(
                for: Client.self, PlowRoute.self, RouteStop.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = container.mainContext
            defaults = try #require(UserDefaults(suiteName: "ActiveRouteStoreTests-\(UUID().uuidString)"))
            client = Client(name: "Alder Co", phone: "", address: "1 Main St", operatorID: "op")
            context.insert(client)
            route = PlowRoute(name: "Tuesday", operatorID: "op")
            context.insert(route)
            for i in 0..<stopCount {
                let stop = RouteStop(order: i, client: client)
                stop.route = route
                context.insert(stop)
            }
            try context.save()
        }

        /// A store as the app would build one at launch: same defaults and data.
        func makeStore(_ surfaces: FakeRouteSurfaces = FakeRouteSurfaces()) -> ActiveRouteStore {
            let store = ActiveRouteStore(defaults: defaults, surfaces: surfaces, now: { [unowned self] in clock })
            store.configure(context: context)
            return store
        }
    }

    @Test func startBeginsAtTheFirstStop() throws {
        let h = try Harness()
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        #expect(store.isActive)
        #expect(store.currentStopIndex == 0)
        #expect(store.isFirstStopPromptPending)
        #expect(surfaces.calls.last == "start")
        #expect(surfaces.last?.currentStopNumber == 1)
        #expect(surfaces.last?.totalStops == 3)
    }

    // Bug #2: a killed app lost the route. A second store built from the same
    // saved data stands in for the relaunched app.
    @Test func aRelaunchComesBackAtTheSameStop() throws {
        let h = try Harness()
        let first = h.makeStore()
        first.start(h.route)
        first.completeCurrentStop()
        let stopStarted = try #require(first.stopStartedAt)

        let surfaces = FakeRouteSurfaces()
        let relaunched = h.makeStore(surfaces)
        #expect(relaunched.isActive)
        #expect(relaunched.route?.id == h.route.id)
        #expect(relaunched.currentStopIndex == 1)
        #expect(relaunched.stopStartedAt == stopStarted)
        #expect(!relaunched.isFirstStopPromptPending)
        #expect(surfaces.calls == ["resume"])
    }

    @Test func completingAStopRecordsTheVisitAndAdvances() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        h.clock += 12 * 60
        #expect(store.completeCurrentStop() == .advanced(nextStopIndex: 1))
        #expect(h.client.totalVisits == 1)
        #expect(abs(h.client.totalServiceMinutes - 12) < 0.001)
        #expect(h.client.lastServiceDate == h.clock)
        #expect(store.stopStartedAt == h.clock)
    }

    @Test func theLastStopFinishesTheRouteButDoesNotEndIt() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        #expect(store.completeCurrentStop() == .advanced(nextStopIndex: 1))
        #expect(store.isLastStop)
        #expect(store.completeCurrentStop() == .finishedLastStop)
        #expect(store.allStopsDone)
        #expect(store.isActive)
        #expect(store.completeCurrentStop() == .allStopsAlreadyDone)
        #expect(h.client.totalVisits == 2)
    }

    @Test func nothingHappensWithoutAnActiveRoute() throws {
        let h = try Harness()
        let store = h.makeStore()
        #expect(store.completeCurrentStop() == .noActiveRoute)
        #expect(h.client.totalVisits == 0)
    }

    @Test func endingClearsTheCheckpoint() throws {
        let h = try Harness()
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        store.end()
        #expect(!store.isActive)
        #expect(surfaces.calls.last == "end")
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) == nil)
        #expect(!h.makeStore().isActive)
    }

    @Test func aDeletedRouteIsNotRestored() throws {
        let h = try Harness()
        h.makeStore().start(h.route)
        h.context.delete(h.route)
        try h.context.save()
        let surfaces = FakeRouteSurfaces()
        let relaunched = h.makeStore(surfaces)
        #expect(!relaunched.isActive)
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) == nil)
        #expect(surfaces.calls == ["clear"])
    }

    @Test func aRestoredIndexNeverPointsPastTheStops() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        store.completeCurrentStop()
        store.completeCurrentStop()          // on stop 3 of 3
        for stop in h.route.sortedStops.dropFirst() { h.context.delete(stop) }
        try h.context.save()                 // two stops removed while closed
        let relaunched = h.makeStore()
        #expect(relaunched.currentStopIndex == 1)
        #expect(relaunched.allStopsDone)
    }

    // The custom stop carries the client's ID on purpose: without it, the
    // visit would go nowhere even if the isCustomStop guard were removed, and
    // the test could never fail (found in review).
    @Test func customStopsDoNotCountAsClientVisits() throws {
        let h = try Harness(stopCount: 0)
        let custom = RouteStop(order: 0, customName: "Salt depot")
        custom.clientID = h.client.id
        custom.route = h.route
        h.context.insert(custom)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        #expect(store.completeCurrentStop() == .finishedLastStop)
        #expect(h.client.totalVisits == 0)
    }

    // Another device reorders the route while this one is closed: the
    // relaunch must stay on the same client, not the same position.
    @Test func aRelaunchFollowsTheStopNotThePosition() throws {
        let h = try Harness(stopCount: 3)
        // Not configured, so it doesn't observe saves: a closed app can't
        // notice the reorder and fix its own checkpoint. (A configured store
        // here did exactly that, and hid a restore that ignored the stop ID.)
        let store = ActiveRouteStore(defaults: h.defaults, surfaces: FakeRouteSurfaces(), now: { Date() })
        store.start(h.route)
        store.completeCurrentStop()
        let current = try #require(store.currentStop?.id)
        let stops = h.route.sortedStops
        stops[1].order = 0; stops[0].order = 1        // swap stops 1 and 2
        try h.context.save()
        let relaunched = h.makeStore()
        #expect(relaunched.currentStop?.id == current)
        #expect(relaunched.currentStopIndex == 0)
    }

    // The same while the app is open: the store re-checks when data changes.
    @Test func aReorderWhileActiveKeepsTheCurrentStop() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        store.completeCurrentStop()
        let current = try #require(store.currentStop?.id)
        let stops = h.route.sortedStops
        stops[1].order = 0; stops[0].order = 1
        store.validate()
        #expect(store.currentStop?.id == current)
    }

    // Deleted on another device mid-route: the store must let go, not keep
    // driving a deleted model.
    @Test func aRouteDeletedWhileActiveEndsIt() throws {
        let h = try Harness()
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        h.context.delete(h.route)
        try h.context.save()
        store.validate()
        #expect(!store.isActive)
        #expect(surfaces.calls.last == "end")
        #expect(surfaces.last?.routeName == "Tuesday")
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) == nil)
    }

    @Test func anUnreadableCheckpointIsRemoved() throws {
        let h = try Harness()
        h.defaults.set(Data("not json".utf8), forKey: ActiveRouteStore.checkpointKey)
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        #expect(!store.isActive)
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) == nil)
        #expect(surfaces.calls == ["clear"])
    }

    // Delete Account & Data must remove the checkpoint whether or not this
    // process has the route active.
    @Test func eraseAllRemovesACheckpointEvenWithNoActiveRoute() throws {
        let h = try Harness()
        h.makeStore().start(h.route)
        let other = ActiveRouteStore(defaults: h.defaults, surfaces: FakeRouteSurfaces(), now: { Date() })
        #expect(!other.isActive)                      // never configured
        other.eraseAll()
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) == nil)
    }

    // Which Live Activity a relaunch adopts: only a running one for this route.
    @Test func onlyARunningActivityForThisRouteIsAdopted() {
        let r = "route-1"
        #expect(LiveActivityCandidate.toAdopt(from: [
            .init(id: "ended", routeID: r, isRunning: false),
            .init(id: "other", routeID: "route-2", isRunning: true),
            .init(id: "live", routeID: r, isRunning: true),
        ], routeID: r) == "live")
        #expect(LiveActivityCandidate.toAdopt(from: [
            .init(id: "ended", routeID: r, isRunning: false),
        ], routeID: r) == nil)
    }
}
