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
    func endStray(keeping routeID: UUID?) { calls.append(routeID == nil ? "endStray(all)" : "endStray(others)") }
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
        #expect(surfaces.calls == ["endStray(others)", "resume"])
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
        #expect(surfaces.calls == ["endStray(all)"])
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

    @Test func customStopsDoNotCountAsClientVisits() throws {
        let h = try Harness(stopCount: 0)
        let custom = RouteStop(order: 0, customName: "Salt depot")
        custom.route = h.route
        h.context.insert(custom)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        #expect(store.completeCurrentStop() == .finishedLastStop)
        #expect(h.client.totalVisits == 0)
    }
}
