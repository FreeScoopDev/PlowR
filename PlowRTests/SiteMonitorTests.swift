import Foundation
import CoreLocation
import Testing
@testable import PlowR

/// iOS's monitor as `SiteMonitor` sees it: the areas held, by identifier.
final class FakeSiteConditions: SiteConditions {
    var held: [String: SiteArea] = [:]
    var added: [String] = []
    var removed: [String] = []
    func identifiers() async -> [String] { Array(held.keys) }
    func add(_ area: SiteArea) async {
        held[area.id] = area
        added.append(area.id)
    }
    func remove(_ id: String) async {
        held[id] = nil
        removed.append(id)
    }
}

final class FakeSiteSession: SiteSession {
    let need: CLServiceSession.AuthorizationRequirement
    var invalidated = false
    init(_ need: CLServiceSession.AuthorizationRequirement) { self.need = need }
    func invalidate() { invalidated = true }
}

struct FakeDiagnostics: SiteDiagnostics {
    var accuracyLimited = false
    var conditionLimitExceeded = false
    var conditionUnsupported = false
    var authorizationDenied = false
    var authorizationDeniedGlobally = false
    var authorizationRestricted = false
    var persistenceUnavailable = false
    var serviceSessionRequired = false
    var insufficientlyInUse = false
    var authorizationRequestInProgress = false
}

final class FakeErasing: SiteErasing {
    var erased = 0
    func eraseAll() { erased += 1 }
}

/// Job-site areas on CLMonitor: placing, iOS's answers turned into arrivals
/// and departures at iOS's own times, the session, and erasing.
@MainActor
struct SiteMonitorTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private let placed = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - SiteEvents.crossing

    @Test func theFirstAnswerAfterPlacingIsNotACrossing() {
        // Inside straight away: already there.
        #expect(SiteEvents.crossing(previous: .unknown, placedAt: placed, presence: .inside, at: placed + 5)
            == .insideWhenPlaced(placed + 5))
        #expect(SiteEvents.crossing(previous: .unknown, placedAt: placed, presence: .inside,
                                    at: placed + SiteTimes.settleTime - 1) == .insideWhenPlaced(placed + 59))
        // Outside: nothing happened.
        #expect(SiteEvents.crossing(previous: .unknown, placedAt: placed, presence: .outside, at: placed + 5) == .none)
        // A first "inside" a minute or more on: iOS answered only when the
        // phone crossed, as legacy monitoring did.
        #expect(SiteEvents.crossing(previous: .unknown, placedAt: placed, presence: .inside,
                                    at: placed + SiteTimes.settleTime) == .entered(placed + 60))
    }

    @Test func aChangeOfPlaceIsACrossingAtItsOwnTime() {
        #expect(SiteEvents.crossing(previous: .outside, placedAt: placed, presence: .inside, at: placed + 5)
            == .entered(placed + 5))
        #expect(SiteEvents.crossing(previous: .inside, placedAt: placed, presence: .outside, at: placed + 900)
            == .exited(placed + 900))
        // The same place again, or "unknown": nothing.
        #expect(SiteEvents.crossing(previous: .inside, placedAt: placed, presence: .inside, at: placed + 900) == .none)
        #expect(SiteEvents.crossing(previous: .outside, placedAt: placed, presence: .outside, at: placed + 9) == .none)
        #expect(SiteEvents.crossing(previous: .inside, placedAt: placed, presence: .unknown, at: placed + 9) == .none)
    }

    @Test func onlySatisfiedAndUnsatisfiedSayWhereThePhoneIs() {
        #expect(SiteEvents.presence(of: .satisfied) == .inside)
        #expect(SiteEvents.presence(of: .unsatisfied) == .outside)
        #expect(SiteEvents.presence(of: .unknown) == nil)
        #expect(SiteEvents.presence(of: .unmonitored) == nil)
    }

    @Test func diagnosticsAreNamed() {
        #expect(SiteEvents.limits(of: FakeDiagnostics()).isEmpty)
        #expect(SiteEvents.limits(of: FakeDiagnostics(accuracyLimited: true)) == [.accuracyLimited])
        let many = FakeDiagnostics(conditionLimitExceeded: true, authorizationDenied: true, insufficientlyInUse: true)
        #expect(SiteEvents.limits(of: many) == [.conditionLimitExceeded, .authorizationDenied, .insufficientlyInUse])
        // Each flag maps to its own limit.
        let all = FakeDiagnostics(accuracyLimited: true, conditionLimitExceeded: true, conditionUnsupported: true,
                                  authorizationDenied: true, authorizationDeniedGlobally: true,
                                  authorizationRestricted: true, persistenceUnavailable: true,
                                  serviceSessionRequired: true, insufficientlyInUse: true,
                                  authorizationRequestInProgress: true)
        #expect(SiteEvents.limits(of: all) == SiteLimit.allCases)
    }

    @Test func theSessionAsksForNothingNewAndOnlyWhileAreasAreWatched() {
        #expect(SiteEvents.sessionNeed(status: .authorizedAlways, hasAreas: true) == .always)
        #expect(SiteEvents.sessionNeed(status: .authorizedWhenInUse, hasAreas: true) == .whenInUse)
        #expect(SiteEvents.sessionNeed(status: .notDetermined, hasAreas: true) == nil)
        #expect(SiteEvents.sessionNeed(status: .denied, hasAreas: true) == nil)
        #expect(SiteEvents.sessionNeed(status: .authorizedAlways, hasAreas: false) == nil)
    }

    // MARK: - SiteMonitor

    @MainActor
    final class Rig {
        let h: Harness
        let store: ActiveRouteStore
        let conditions = FakeSiteConditions()
        let legacy = AccountEraserTests.FakeRegions()
        var sessions: [FakeSiteSession] = []
        let accuracy: CLAccuracyAuthorization
        let authorization: CLAuthorizationStatus

        init(stopCount: Int = 3, authorization: CLAuthorizationStatus = .authorizedAlways,
             accuracy: CLAccuracyAuthorization = .fullAccuracy) throws {
            h = try Harness(stopCount: stopCount)
            for (i, stop) in h.route.sortedStops.enumerated() {
                stop.latitude = 43 + Double(i) / 100
                stop.longitude = -79
            }
            self.accuracy = accuracy
            self.authorization = authorization
            store = h.makeStore()
        }

        /// A monitor on the harness's preferences, as at a (re)launch.
        func monitor(conditions: SiteConditions? = nil) -> SiteMonitor {
            SiteMonitor(defaults: h.defaults, now: { [unowned self] in h.clock }, route: { [unowned self] in store },
                        makeSession: { [unowned self] need in
                            let session = FakeSiteSession(need)
                            sessions.append(session)
                            return session
                        },
                        conditions: conditions ?? self.conditions, legacy: legacy,
                        authorization: authorization, accuracy: accuracy)
        }

        func id(_ index: Int) -> String { h.route.sortedStops[index].id.uuidString }
        func area(_ index: Int) -> SiteArea {
            let stop = h.route.sortedStops[index]
            return SiteArea(id: stop.id.uuidString, latitude: stop.latitude, longitude: stop.longitude)
        }
    }

    @Test func areasArePlacedOnceAndMovedAreasAgain() async throws {
        let rig = try Rig()
        let monitor = rig.monitor()
        monitor.watch([rig.area(0)])
        await monitor.settled()
        #expect(rig.conditions.added == [rig.id(0)])
        // The same area again: left alone, so iOS needn't work it out again.
        monitor.watch([rig.area(0)])
        await monitor.settled()
        #expect(rig.conditions.added == [rig.id(0)] && rig.conditions.removed.isEmpty)
        // Its pin moved: placed again.
        var moved = rig.area(0)
        moved.latitude += 0.001
        monitor.watch([moved])
        await monitor.settled()
        #expect(rig.conditions.removed == [rig.id(0)])
        #expect(rig.conditions.added == [rig.id(0), rig.id(0)])
        #expect(rig.conditions.held[rig.id(0)] == moved)
        monitor.watch([])
        await monitor.settled()
        #expect(rig.conditions.held.isEmpty)
    }

    @Test func nothingIsTouchedBeforeTheRouteSaysWhatItWants() async throws {
        // A relaunch: iOS still holds an area, and the route isn't restored yet.
        let rig = try Rig()
        rig.conditions.held[rig.id(0)] = rig.area(0)
        let monitor = rig.monitor()
        monitor.authorizationChanged(to: .authorizedAlways, accuracy: .fullAccuracy)
        await monitor.settled()
        #expect(rig.conditions.held.count == 1 && rig.conditions.removed.isEmpty)
        #expect(rig.legacy.monitoredRegions.count == 2)
    }

    @Test func legacyAreasGiveWayToTheMonitorsOnes() async throws {
        // A route running across the update from 1.7: its regions are stopped
        // and the route's areas placed in the monitor.
        let rig = try Rig()
        let monitor = rig.monitor()
        monitor.watch([rig.area(0), rig.area(1)])
        await monitor.settled()
        #expect(rig.legacy.monitoredRegions.isEmpty)
        #expect(Set(rig.conditions.held.keys) == [rig.id(0), rig.id(1)])
    }

    @Test func strayAreasGoAndLostOnesArePlacedAgain() async throws {
        let rig = try Rig()
        let monitor = rig.monitor()
        monitor.watch([rig.area(0)])
        await monitor.settled()
        // One PlowR doesn't know (an erase that didn't finish, say), and its
        // own lost by iOS.
        rig.conditions.held = ["stray": rig.area(2)]
        monitor.watch([rig.area(0)])
        await monitor.settled()
        #expect(Set(rig.conditions.held.keys) == [rig.id(0)])
        #expect(rig.conditions.removed == ["stray"])
    }

    @Test func iOSsOwnTimesAreTheArrivalAndDeparture() async throws {
        let rig = try Rig()
        let monitor = rig.monitor()
        rig.store.start(rig.h.route)
        monitor.watch([rig.area(0)])
        await monitor.settled()
        let began = rig.h.clock
        monitor.receive(rig.id(0), presence: .outside, at: began + 3)
        // Handed over ten minutes late (the app was suspended): iOS's time counts.
        rig.h.clock = began + 1200
        monitor.receive(rig.id(0), presence: .inside, at: began + 400)
        #expect(rig.store.site.arrivedAt == began + 400)
        monitor.receive(rig.id(0), presence: .outside, at: began + 1100)
        #expect(rig.store.site.leftAt == began + 1100)
        // The route screen's text offer goes by the same time.
        #expect(monitor.lastExit?.stopID == rig.id(0) && monitor.lastExit?.time == began + 1100)
    }

    @Test func alreadyInsideWhenPlacedIsArrivalNotCaught() async throws {
        let rig = try Rig()
        let monitor = rig.monitor()
        rig.store.start(rig.h.route)
        monitor.watch([rig.area(0)])
        await monitor.settled()
        monitor.receive(rig.id(0), presence: .inside, at: rig.h.clock + 4)
        #expect(rig.store.site.arrivalUnseen && rig.store.site.arrivedAt == nil)
    }

    @Test func whereThePhoneWasSurvivesARelaunch() async throws {
        let rig = try Rig()
        rig.store.start(rig.h.route)
        let before = rig.monitor()
        before.watch([rig.area(0)])
        await before.settled()
        before.receive(rig.id(0), presence: .outside, at: rig.h.clock + 3)
        // Relaunched by iOS for the arrival, 20 s in: "outside" was heard
        // before, so this is a crossing, not a first answer.
        let after = rig.monitor()
        after.receive(rig.id(0), presence: .inside, at: rig.h.clock + 20)
        #expect(rig.store.site.arrivedAt == rig.h.clock + 20)
        // And an area iOS still holds isn't placed afresh at the next watch.
        after.watch([rig.area(0)])
        await after.settled()
        #expect(rig.conditions.added == [rig.id(0)])
    }

    @Test func anAreaThatIsntPlowRsIsIgnored() async throws {
        let rig = try Rig()
        rig.store.start(rig.h.route)
        let monitor = rig.monitor()
        monitor.receive(rig.id(0), presence: .inside, at: rig.h.clock + 400)
        #expect(rig.store.site == SiteTimes())
    }

    @Test func approximateLocationPlacesNothingAndPreciseAgainPlacesAllAfresh() async throws {
        let rig = try Rig(accuracy: .reducedAccuracy)
        rig.conditions.held[rig.id(0)] = rig.area(0)       // from before it was turned off
        let monitor = rig.monitor()
        monitor.watch([rig.area(0), rig.area(1)])
        await monitor.settled()
        #expect(rig.conditions.added.isEmpty && rig.conditions.removed.isEmpty)
        monitor.authorizationChanged(to: .authorizedAlways, accuracy: .fullAccuracy)
        await monitor.settled()
        #expect(rig.conditions.removed == [rig.id(0)])
        #expect(Set(rig.conditions.added) == [rig.id(0), rig.id(1)])
    }

    @Test func iOSSayingAccuracyIsLimitedShowsThePreciseNote() async throws {
        let rig = try Rig()
        rig.store.start(rig.h.route)
        let monitor = rig.monitor()
        monitor.watch([rig.area(0)])
        await monitor.settled()
        monitor.noteLimits([.accuracyLimited], id: rig.id(0))
        #expect(monitor.accuracyLimited)
        #expect(RouteGPS.needsPrecise(status: .authorizedAlways, accuracy: .fullAccuracy,
                                      areasLimited: monitor.accuracyLimited, isMac: false))
        // Not a crossing: where the phone was is unchanged.
        #expect(rig.store.site == SiteTimes())
        monitor.authorizationChanged(to: .authorizedAlways, accuracy: .fullAccuracy)
        #expect(!monitor.accuracyLimited)
        monitor.noteLimits([.accuracyLimited], id: rig.id(0))
        monitor.receive(rig.id(0), presence: .outside, at: rig.h.clock + 3)
        #expect(!monitor.accuracyLimited)
        // Others are logged and leave the note alone.
        monitor.noteLimits([.conditionLimitExceeded], id: rig.id(0))
        #expect(!monitor.accuracyLimited)
    }

    @Test func locationAllowedOnlyNowMakesTheNextAnswerAFirstAnswer() async throws {
        let rig = try Rig(authorization: .denied)
        rig.store.start(rig.h.route)
        let monitor = rig.monitor()
        monitor.watch([rig.area(0)])
        await monitor.settled()
        monitor.receive(rig.id(0), presence: .outside, at: rig.h.clock + 3)
        rig.h.clock += 600
        monitor.authorizationChanged(to: .authorizedAlways, accuracy: .fullAccuracy)
        // The crew may have driven in while it was off: not an arrival.
        monitor.receive(rig.id(0), presence: .inside, at: rig.h.clock + 2)
        #expect(rig.store.site.arrivedAt == nil && rig.store.site.arrivalUnseen)
    }

    @Test func aSessionIsHeldOnlyWhileAreasAreWatched() async throws {
        let rig = try Rig()
        let monitor = rig.monitor()
        #expect(rig.sessions.isEmpty)
        monitor.watch([rig.area(0)])
        await monitor.settled()
        #expect(rig.sessions.count == 1 && rig.sessions[0].need == .always && !rig.sessions[0].invalidated)
        monitor.watch([rig.area(1)])
        await monitor.settled()
        #expect(rig.sessions.count == 1)
        monitor.watch([])
        await monitor.settled()
        #expect(rig.sessions[0].invalidated)
        // Down to While Using mid-route: a session at that level, nothing asked.
        monitor.watch([rig.area(0)])
        monitor.authorizationChanged(to: .authorizedWhenInUse, accuracy: .fullAccuracy)
        await monitor.settled()
        #expect(rig.sessions.last?.need == .whenInUse)
        #expect(rig.sessions.dropLast().allSatisfy { $0.invalidated })
    }

    @Test func aRelaunchRetakesTheSessionFromWhatWasPlaced() async throws {
        let rig = try Rig()
        let before = rig.monitor()
        before.watch([rig.area(0)])
        await before.settled()
        // Relaunched in the background: the route hasn't said yet, iOS still
        // holds the area. `start()` takes the session at once from the record.
        let after = rig.monitor()
        after.updateSession()
        #expect(rig.sessions.count == 2 && rig.sessions[1].need == .always && !rig.sessions[1].invalidated)
        // Nothing placed before: none.
        let fresh = try Rig()
        fresh.monitor().updateSession()
        #expect(fresh.sessions.isEmpty)
    }

    @Test func eraseRemovesEveryAreaTheRecordAndTheSession() async throws {
        let rig = try Rig()
        let monitor = rig.monitor()
        rig.conditions.held["stray"] = rig.area(2)
        monitor.watch([rig.area(0), rig.area(1)])
        await monitor.settled()
        #expect(rig.h.defaults.data(forKey: SiteEvents.placedKey) != nil)
        monitor.eraseAll()
        await monitor.settled()
        #expect(rig.conditions.held.isEmpty)
        #expect(rig.h.defaults.data(forKey: SiteEvents.placedKey) == nil)
        #expect(rig.sessions.allSatisfy { $0.invalidated })
        #expect(rig.legacy.monitoredRegions.isEmpty)
    }

    @Test func anEraseBeforeTheMonitorOpensHappensOnceItDoes() async throws {
        // No monitor open yet (protected data not available): the record
        // goes now, and the next monitor to open removes what iOS holds.
        let rig = try Rig()
        rig.conditions.held[rig.id(0)] = rig.area(0)
        SiteEvents.save([PlacedSite(rig.area(0), placedAt: rig.h.clock)], to: rig.h.defaults)
        let unopened = SiteMonitor(defaults: rig.h.defaults, route: { rig.store })
        unopened.eraseAll()
        await unopened.settled()
        #expect(rig.h.defaults.data(forKey: SiteEvents.placedKey) == nil)
        let next = rig.monitor()
        next.watch([])
        await next.settled()
        #expect(rig.conditions.held.isEmpty)
    }

    // MARK: - Delivered late

    @Test func aLateEntryFromBeforeCompletingDoesntCancelTheDeparture() throws {
        let h = try Harness()
        for (i, stop) in h.route.sortedStops.enumerated() {
            stop.latitude = 43 + Double(i) / 100
            stop.longitude = -79
        }
        let store = h.makeStore()
        store.start(h.route)
        let run = try #require(store.runID)
        let first = h.route.sortedStops[0]
        h.clock += 900
        store.completeShownStop()       // Control Center, phone locked: nothing heard yet
        let completed = h.clock
        // Handed over once the phone was unlocked, from before completing.
        store.siteEntered(first.id.uuidString, at: completed - 600)
        store.siteExited(first.id.uuidString, at: completed - 300)
        #expect(store.departures.map(\.stopID) == [first.id])
        #expect(ServiceLog.runRecord(run: run, stop: first.id, in: h.context)?.leftAt == nil)
        // The departure after completing is still caught.
        store.siteExited(first.id.uuidString, at: completed + 120)
        #expect(ServiceLog.runRecord(run: run, stop: first.id, in: h.context)?.leftAt == completed + 120)
        #expect(store.departures.isEmpty)
    }

    // MARK: - Delete Account & Data

    @Test func bothDeletePathsEraseTheAreas() throws {
        let account = try AccountEraserTests.Account()
        defer { account.removeFiles() }
        #expect(account.eraser().eraseAll().isEmpty)
        #expect(account.sites.erased == 1)

        let other = try AccountEraserTests.Account()
        defer { other.removeFiles() }
        #expect(other.eraser().removeFromThisDevice().isEmpty)
        #expect(other.sites.erased == 1)
    }
}
