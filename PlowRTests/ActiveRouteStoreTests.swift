//
//  ActiveRouteStoreTests.swift
//  PlowRTests
//

import Testing
import CoreData
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

extension ActiveRouteStore {
    /// Completes the stop the screen shows: the current one, or once every stop
    /// is done, the last one (a repeated tap on Complete Route).
    @discardableResult
    func completeShownStop() -> CompletionResult {
        completeCurrentStop(expecting: currentStopID ?? sortedStops.last?.id ?? UUID())
    }
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
        /// One client per stop, so crediting the wrong client is detectable.
        var clients: [Client] = []
        var client: Client { clients[0] }
        let route: PlowRoute

        init(stopCount: Int = 3) throws {
            container = try ModelContainer(
                for: Client.self, PlowRoute.self, RouteStop.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            )
            context = container.mainContext
            defaults = try #require(UserDefaults(suiteName: "ActiveRouteStoreTests-\(UUID().uuidString)"))
            route = PlowRoute(name: "Tuesday", operatorID: "op")
            context.insert(route)
            for i in 0..<max(stopCount, 1) {
                let client = Client(name: "Client \(i)", phone: "", address: "\(i) Main St", operatorID: "op")
                context.insert(client)
                clients.append(client)
            }
            for i in 0..<stopCount {
                let stop = RouteStop(order: i, client: clients[i])
                stop.route = route
                context.insert(stop)
            }
            try context.save()
        }

        /// A store for "before the app was closed": not configured, so it doesn't
        /// observe saves. A closed app can't react to changes; a configured
        /// store here would quietly fix its own checkpoint and hide bugs (two
        /// tests were contaminated that way, found in review).
        func makeClosedAppStore() -> ActiveRouteStore {
            ActiveRouteStore(defaults: defaults, surfaces: FakeRouteSurfaces(), now: { [unowned self] in clock })
        }

        /// A store as the app would build one at launch: same defaults and data.
        func makeStore(_ surfaces: FakeRouteSurfaces = FakeRouteSurfaces(),
                       fetchRoutes: ((ModelContext) throws -> [PlowRoute])? = nil) -> ActiveRouteStore {
            let store = ActiveRouteStore(defaults: defaults, surfaces: surfaces, now: { [unowned self] in clock },
                                         fetchRoutes: fetchRoutes ?? { try $0.fetch(FetchDescriptor<PlowRoute>()) })
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
        #expect(surfaces.last?.completedStops == 0)
    }

    // The widget's "N done" comes from completedStops, which nothing checked.
    // After the last stop it must read "2 of 2", never "3 of 2".
    @Test func progressCountsCompletedStops() throws {
        let h = try Harness(stopCount: 2)
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        store.completeShownStop()
        #expect(surfaces.last?.completedStops == 1)
        #expect(surfaces.last?.currentStopNumber == 2)
        store.completeShownStop()
        #expect(surfaces.last?.completedStops == 2)
        #expect(surfaces.last?.currentStopNumber == 2)
        #expect(surfaces.last?.totalStops == 2)
        #expect(surfaces.last?.currentStopName == "All stops complete")
    }

    // Bug #2: a killed app lost the route. A second store built from the same
    // saved data stands in for the relaunched app.
    @Test func aRelaunchComesBackAtTheSameStop() throws {
        let h = try Harness()
        let first = h.makeStore()
        first.start(h.route)
        first.completeShownStop()
        let stopStarted = try #require(first.stopStartedAt)
        // Time passes before the relaunch. Without it, a restarted timer and
        // the saved one are the same instant, so the timer check below could
        // never fail (found by a test audit).
        h.clock += 20 * 60

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
        #expect(store.completeShownStop() == .advanced(nextStopIndex: 1))
        #expect(h.client.totalVisits == 1)
        #expect(abs(h.client.totalServiceMinutes - 12) < 0.001)
        #expect(h.client.lastServiceDate == h.clock)
        #expect(store.stopStartedAt == h.clock)
    }

    @Test func theLastStopFinishesTheRouteButDoesNotEndIt() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        #expect(store.completeShownStop() == .advanced(nextStopIndex: 1))
        #expect(store.isLastStop)
        #expect(store.completeShownStop() == .finishedLastStop)
        #expect(store.allStopsDone)
        #expect(store.isActive)
        #expect(store.completeShownStop() == .allStopsAlreadyDone)
        #expect(h.clients[0].totalVisits == 1)
        #expect(h.clients[1].totalVisits == 1)
    }

    @Test func nothingHappensWithoutAnActiveRoute() throws {
        let h = try Harness()
        let store = h.makeStore()
        #expect(store.completeShownStop() == .noActiveRoute)
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
        h.makeClosedAppStore().start(h.route)
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
        let store = h.makeClosedAppStore()
        store.start(h.route)
        store.completeShownStop()
        store.completeShownStop()          // on stop 3 of 3
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
        #expect(store.completeShownStop() == .finishedLastStop)
        #expect(h.client.totalVisits == 0)
    }

    // Another device reorders the route while this one is closed: the
    // relaunch must stay on the same client, not the same position.
    @Test func aRelaunchFollowsTheStopNotThePosition() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeClosedAppStore()
        store.start(h.route)
        store.completeShownStop()
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
        store.completeShownStop()
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
        try h.context.save()                          // the save observer re-checks; no manual validate()
        #expect(!store.isActive)
        #expect(surfaces.calls.last == "end")
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
        let surfaces = FakeRouteSurfaces()
        let other = ActiveRouteStore(defaults: h.defaults, surfaces: surfaces, now: { Date() })
        #expect(!other.isActive)                      // never configured
        other.eraseAll()
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) == nil)
        // A Live Activity or an "active" widget left by that route goes too.
        #expect(surfaces.calls == ["clear"])
    }

    @Test func eraseAllEndsAnActiveRoute() throws {
        let h = try Harness()
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        store.eraseAll()
        #expect(!store.isActive)
        #expect(surfaces.calls.suffix(2) == ["end", "clear"])
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) == nil)
    }

    // Another device's changes arrive as a remote-change notification, not as
    // a save here. In-memory stores never post it, so the test posts it by
    // hand, with a fetch that reports the route deleted elsewhere.
    @Test func aRemoteChangeIsCheckedLikeASave() throws {
        let h = try Harness()
        let surfaces = FakeRouteSurfaces()
        var deletedElsewhere = false
        let store = h.makeStore(surfaces, fetchRoutes: { context in
            if deletedElsewhere { return [] }
            return try context.fetch(FetchDescriptor<PlowRoute>())
        })
        store.start(h.route)
        deletedElsewhere = true
        NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        #expect(!store.isActive)
        #expect(surfaces.calls.last == "end")
    }

    // An earlier stop deleted mid-route leaves the same client current but
    // moves it up. The saved position must move too: a relaunch that later
    // falls back to it would otherwise skip a client.
    @Test func deletingAnEarlierStopMovesTheSavedPosition() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()                           // on Client 1, position 1
        let current = try #require(store.currentStopID)
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        #expect(store.currentStopID == current)
        #expect(store.currentStopIndex == 0)
        let data = try #require(h.defaults.data(forKey: ActiveRouteStore.checkpointKey))
        let saved = try JSONDecoder().decode(ActiveRouteStore.Checkpoint.self, from: data)
        #expect(saved.currentStopIndex == 0)
        #expect(saved.currentStopID == current)
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

    // Found in review: the current stop deleted on another device used to hand
    // its timer, and the next Complete, to the following client.
    @Test func aDeletedCurrentStopIsNeverCreditedToTheNextClient() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        let shown = try #require(store.currentStop?.id)       // what the screen showed
        h.clock += 30 * 60
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        #expect(store.completeCurrentStop(expecting: shown) == .stopChanged)
        #expect(h.clients[1].totalVisits == 0)
        #expect(store.currentStop?.id == h.route.sortedStops.first?.id)
        #expect(store.stopStartedAt == h.clock)               // the new stop's timer starts now
    }

    // A change that keeps the index (the current stop deleted, the next moving
    // into its place) must still refresh the Lock Screen and the checkpoint.
    @Test func aDeletedCurrentStopRefreshesTheLiveActivity() throws {
        let h = try Harness(stopCount: 3)
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        #expect(surfaces.calls.last == "update")
        #expect(surfaces.last?.currentStopName == "Client 1")
        #expect(surfaces.last?.totalStops == 2)
        // The checkpoint itself must have moved on (a relaunch alone can't tell:
        // its fallback lands on the same client even from a stale checkpoint).
        let data = try #require(h.defaults.data(forKey: ActiveRouteStore.checkpointKey))
        let saved = try JSONDecoder().decode(ActiveRouteStore.Checkpoint.self, from: data)
        #expect(saved.currentStopID == store.currentStopID)
        #expect(saved.stopStartedAt == store.stopStartedAt)
    }

    // Review 3's probe: the relaunch path used to keep the deleted stop's
    // timer for the next client (35 minutes credited for 5 of work).
    @Test func aCurrentStopDeletedWhileClosedStartsTheNextTimerAtRelaunch() throws {
        let h = try Harness(stopCount: 3)
        h.makeClosedAppStore().start(h.route)          // stop 1 started at 08:00
        h.clock += 30 * 60
        h.context.delete(h.route.sortedStops[0])
        try h.context.save()
        let relaunched = h.makeStore()                 // reopened at 08:30
        #expect(relaunched.currentStop?.clientName == "Client 1")
        #expect(relaunched.stopStartedAt == h.clock)
        h.clock += 5 * 60
        relaunched.completeShownStop()
        #expect(abs(h.clients[1].totalServiceMinutes - 5) < 0.001)
    }

    // Every stop done, then a stop added elsewhere while closed: it becomes
    // current with its own timer, not the last completion's.
    @Test func aStopAddedAfterAllWereDoneGetsItsOwnTimer() throws {
        let h = try Harness(stopCount: 1)
        let closed = h.makeClosedAppStore()
        closed.start(h.route)
        closed.completeShownStop()
        #expect(closed.allStopsDone)
        h.clock += 60 * 60
        let late = RouteStop(order: 1, customName: "Late add")
        late.route = h.route
        h.context.insert(late)
        try h.context.save()
        let relaunched = h.makeStore()
        #expect(relaunched.currentStop?.id == late.id)
        #expect(relaunched.stopStartedAt == h.clock)
    }

    // The store can't be read at launch: the route isn't lost, and it comes
    // back as soon as a later check can read it.
    @Test func anUnreadableStoreAtLaunchIsRetried() throws {
        struct Unreadable: Error {}
        let h = try Harness(stopCount: 3)
        let closed = h.makeClosedAppStore()
        closed.start(h.route)
        closed.completeShownStop()
        var failing = true
        let store = h.makeStore(fetchRoutes: { context in
            if failing { throw Unreadable() }
            return try context.fetch(FetchDescriptor<PlowRoute>())
        })
        #expect(!store.isActive)
        #expect(h.defaults.data(forKey: ActiveRouteStore.checkpointKey) != nil)   // kept
        failing = false
        store.validate()
        #expect(store.isActive)
        #expect(store.currentStopIndex == 1)
    }

    // Deleting a later stop changes "of N" without touching the current stop.
    @Test func deletingALaterStopUpdatesTheTotal() throws {
        let h = try Harness(stopCount: 3)
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        h.context.delete(h.route.sortedStops[2])
        try h.context.save()
        #expect(surfaces.calls.last == "update")
        #expect(surfaces.last?.totalStops == 2)
        #expect(surfaces.last?.currentStopName == "Client 0")
    }

    // Review 4: the last stop deleted elsewhere while on screen used to read
    // as "already done", so the screen showed a success recap and recorded nothing.
    @Test func aDeletedLastStopIsReportedAsChanged() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        let shown = try #require(store.currentStopID)          // the last stop, on screen
        h.context.delete(h.route.sortedStops[1])
        try h.context.save()
        #expect(store.completeCurrentStop(expecting: shown) == .stopChanged)
        #expect(h.clients[1].totalVisits == 0)
    }

    // A double tap on a stop that really was completed is still "already done".
    @Test func aDoubleTapOnTheFinishedLastStopIsAlreadyDone() throws {
        let h = try Harness(stopCount: 1)
        let store = h.makeStore()
        store.start(h.route)
        let shown = try #require(store.currentStopID)
        #expect(store.completeCurrentStop(expecting: shown) == .finishedLastStop)
        #expect(store.completeCurrentStop(expecting: shown) == .allStopsAlreadyDone)
        #expect(h.clients[0].totalVisits == 1)
    }
}
