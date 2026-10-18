import Foundation
import CoreLocation
import SwiftData
import Testing
@testable import PlowR

/// Records the areas the store asked iOS to watch.
final class FakeSiteWatching: SiteWatching {
    var watched: [[SiteArea]] = []
    var ids: Set<String> { Set(watched.last?.map(\.id) ?? []) }
    func watch(_ areas: [SiteArea]) { watched.append(areas) }
}

/// GPS arrival and departure: only what was seen, kept through a relaunch,
/// put on the stop's record, and a departure caught after completing.
@MainActor
struct SiteTimesTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - SiteTimes

    @Test func anEntryAfterTheStopBeganIsTheArrivalAndTheFirstOneCounts() {
        var site = SiteTimes()
        site.entered(at: start + 600, settleFrom: start)
        site.exited(at: start + 900)
        site.entered(at: start + 1000, settleFrom: start)     // back for the shovel
        #expect(site.arrivedAt == start + 600)
        #expect(site.leftAt == nil)                               // came back in: hadn't left
        site.exited(at: start + 1500)
        #expect(site.leftAt == start + 1500)
        #expect(!site.arrivalUnseen)
    }

    @Test func alreadyInsideWhenTheStopBeganHasNoArrival() {
        // iOS reporting a phone already in the area, just after it's placed.
        var site = SiteTimes()
        site.entered(at: start + SiteTimes.settleTime - 1, settleFrom: start)
        #expect(site.arrivedAt == nil && site.arrivalUnseen)
        // Out to the truck and back: still not an arrival.
        site.exited(at: start + 300)
        site.entered(at: start + 400, settleFrom: start)
        #expect(site.arrivedAt == nil)
        // At exactly the settle time it is one.
        var later = SiteTimes()
        later.entered(at: start + SiteTimes.settleTime, settleFrom: start)
        #expect(later.arrivedAt == start + SiteTimes.settleTime)
    }

    @Test func leavingWithoutBeingSeenToArriveIsNoArrival() {
        var site = SiteTimes()
        site.exited(at: start + 300)
        #expect(site.arrivalUnseen && site.arrivedAt == nil && site.leftAt == start + 300)
        site.entered(at: start + 900, settleFrom: start)
        #expect(site.arrivedAt == nil)
    }

    // MARK: - The route

    private func pin(_ h: Harness) {
        for (i, stop) in h.route.sortedStops.enumerated() {
            stop.latitude = 43 + Double(i) / 100
            stop.longitude = -79
        }
    }

    private func id(_ stop: RouteStop?) -> String { stop?.id.uuidString ?? "" }

    private func record(_ h: Harness, _ store: ActiveRouteStore, _ stop: RouteStop) -> ServiceRecord? {
        guard let run = store.runID else { return nil }
        return ServiceLog.runRecord(run: run, stop: stop.id, in: h.context)
    }

    @Test func theCurrentStopsAreaIsWatchedAndMovesOn() throws {
        let h = try Harness()
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        let stops = h.route.sortedStops
        #expect(sites.ids == [id(stops[0])])
        #expect(sites.watched.last?.first?.latitude == stops[0].latitude)
        // Left the first stop before completing it: nothing more to wait for.
        h.clock += 600
        store.siteEntered(id(stops[0]), at: h.clock)
        h.clock += 600
        store.siteExited(id(stops[0]), at: h.clock)
        store.completeShownStop()
        #expect(sites.ids == [id(stops[1])])
        // A stop with no pin has no area.
        stops[2].latitude = 0
        stops[2].longitude = 0
        h.clock += 60
        store.completeShownStop()
        #expect(sites.ids == [id(stops[1])])     // waiting on the second's departure only
        store.end()
        #expect(sites.ids == [id(stops[1])])     // which outlives the route
    }

    @Test func arrivalAndDepartureGoOnTheStopsRecord() throws {
        let h = try Harness()
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = h.route.sortedStops[0]
        let began = h.clock
        store.siteEntered(id(stop), at: began + 420)
        store.siteExited(id(stop), at: began + 1500)
        // Another stop's crossings aren't this one's.
        store.siteEntered(id(h.route.sortedStops[1]), at: began + 1600)
        h.clock = began + 1700
        store.completeShownStop()
        let saved = try #require(record(h, store, stop))
        #expect(saved.arrivedAt == began + 420)
        #expect(saved.leftAt == began + 1500)
        #expect(store.departures.isEmpty)        // already seen leaving
        #expect(store.site == SiteTimes())       // the next stop starts afresh
    }

    @Test func aDepartureAfterCompletingIsAddedToTheRecord() throws {
        let h = try Harness()
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        let stops = h.route.sortedStops
        h.clock += 300
        store.siteEntered(id(stops[0]), at: h.clock)
        h.clock += 900
        store.completeShownStop()                // still in the driveway
        #expect(record(h, store, stops[0])?.leftAt == nil)
        #expect(store.departures.map(\.stopID) == [stops[0].id])
        #expect(sites.ids == [id(stops[0]), id(stops[1])])
        // Leaving the first stop doesn't touch the second's times.
        store.siteExited(id(stops[0]), at: h.clock + 120)
        #expect(record(h, store, stops[0])?.leftAt == h.clock + 120)
        #expect(store.site == SiteTimes())
        #expect(store.departures.isEmpty)
        #expect(sites.ids == [id(stops[1])])
    }

    @Test func theLastStopsDepartureIsCaughtAfterEndRouteAndARelaunch() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let run = try #require(store.runID)
        let stop = h.route.sortedStops[0]
        h.clock += 600
        store.completeShownStop()
        store.end()
        // The app is ended; iOS relaunches it when the phone leaves.
        let relaunched = h.makeStore()
        #expect(relaunched.departures.map(\.stopID) == [stop.id])
        relaunched.siteExited(id(stop), at: h.clock + 300)
        #expect(ServiceLog.runRecord(run: run, stop: stop.id, in: h.context)?.leftAt == h.clock + 300)
        #expect(h.makeStore().departures.isEmpty)
    }

    @Test func aDepartureIsOnlyTakenSoonAfterCompletingAndFromThere() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let run = try #require(store.runID)
        let stop = h.route.sortedStops[0]
        store.completeShownStop()
        let completed = h.clock
        // Past the window: driving by later isn't leaving.
        store.siteExited(id(stop), at: completed + SiteDepartures.window + 1)
        #expect(try #require(ServiceLog.runRecord(run: run, stop: stop.id, in: h.context)).leftAt == nil)
        #expect(store.departures.isEmpty)

        // Seen coming in after completing: it wasn't there, so a later exit isn't leaving.
        let second = try Harness(stopCount: 1)
        pin(second)
        let other = second.makeStore()
        other.start(second.route)
        let otherRun = try #require(other.runID)
        let otherStop = second.route.sortedStops[0]
        other.completeShownStop()
        other.siteEntered(id(otherStop), at: second.clock + 60)
        other.siteExited(id(otherStop), at: second.clock + 120)
        #expect(try #require(ServiceLog.runRecord(run: otherRun, stop: otherStop.id, in: second.context)).leftAt == nil)
        #expect(other.departures.isEmpty)
    }

    @Test func aWindowEndsTheWatchToo() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        store.completeShownStop()
        store.end()
        #expect(sites.ids.count == 1)
        h.clock += SiteDepartures.window + 1
        store.validate()        // runs on every save and when the app is active
        #expect(store.departures.isEmpty)
        #expect(sites.ids.isEmpty)
    }

    @Test func theSiteTimesSurviveARelaunch() throws {
        let h = try Harness()
        pin(h)
        let before = h.makeClosedAppStore()
        before.start(h.route)
        let stop = h.route.sortedStops[0]
        before.siteEntered(id(stop), at: h.clock + 400)
        let relaunched = h.makeStore()
        #expect(relaunched.site.arrivedAt == h.clock + 400)
        // Crossings from before the stop began aren't its.
        relaunched.siteExited(id(stop), at: h.clock - 10)
        #expect(relaunched.site.leftAt == nil)
    }

    @Test func aStopChangedBySyncStartsItsTimesAfresh() throws {
        let h = try Harness()
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let first = h.route.sortedStops[0]
        store.siteEntered(id(first), at: h.clock + 400)
        #expect(store.site.arrivedAt != nil)
        // Removed on another device: the next client's stop has no arrival yet.
        h.context.delete(first)
        try h.context.save()
        #expect(store.currentStopID != first.id)
        #expect(store.site == SiteTimes())
    }

    @Test func aStopAwaitingADepartureThatIsCurrentAgainStopsAwaitingIt() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        store.end()
        let stop = h.route.sortedStops[0]
        #expect(store.departures.map(\.stopID) == [stop.id])
        // Its pin corrected 300 m between the passes, so the two areas don't overlap.
        stop.latitude += 300 / 111_195
        // A second pass soon after: leaving the stop now is this run's.
        store.start(h.route)
        #expect(store.departures.isEmpty)
    }

    @Test func anEntrySoonAfterTheAreaIsPlacedAgainIsNoArrival() throws {
        let h = try Harness()
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = h.route.sortedStops[0]
        // The pin was fixed 10 minutes in, and its area placed again.
        let placed = h.clock + 600
        store.siteEntered(id(stop), at: placed + 5, placedAt: placed)
        #expect(store.site.arrivedAt == nil && store.site.arrivalUnseen)
    }

    @Test func anAreaPlacedBeforeTheStopBeganSettlesFromTheStop() throws {
        let h = try Harness()
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        // Placed an hour ago (a completed stop's, say): the stop's own start counts.
        store.siteEntered(id(h.route.sortedStops[0]), at: h.clock + 30, placedAt: h.clock - 3600)
        #expect(store.site.arrivedAt == nil && store.site.arrivalUnseen)
    }

    @Test func onlyLocationAllowedNowResettles() {
        // iOS calls back at every launch with nothing changed: no resettle,
        // or a relaunch for an arrival would throw the arrival away.
        #expect(!SiteMonitor.isNewlyAllowed(from: .authorizedAlways, to: .authorizedAlways))
        #expect(!SiteMonitor.isNewlyAllowed(from: .authorizedWhenInUse, to: .authorizedAlways))
        #expect(SiteMonitor.isNewlyAllowed(from: .notDetermined, to: .authorizedAlways))
        #expect(SiteMonitor.isNewlyAllowed(from: .denied, to: .authorizedWhenInUse))
        #expect(!SiteMonitor.isNewlyAllowed(from: .authorizedAlways, to: .denied))
    }

    @Test func anEntryFromBeforeTheStopBeganIsIgnored() throws {
        let h = try Harness()
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        h.clock += 600
        store.completeShownStop()
        // Reported late, from before the second stop was current.
        store.siteEntered(id(h.route.sortedStops[1]), at: h.clock - 5)
        #expect(store.site == SiteTimes())
    }

    @Test func aStopWithNoPinAwaitsNoDeparture() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()     // no pins
        store.start(h.route)
        store.completeShownStop()
        #expect(store.departures.isEmpty)
    }

    // MARK: - Stops close together, and later stops

    /// Puts the second stop `metres` north of the first.
    private func placeSecond(_ h: Harness, metres: Double) {
        let stops = h.route.sortedStops
        stops[1].latitude = stops[0].latitude + metres / 111_195     // metres per degree of latitude
        stops[1].longitude = stops[0].longitude
    }

    @Test func aStopsDepartureIsntAwaitedWhenTheNextStopsAreaOverlapsIt() throws {
        let h = try Harness()
        pin(h)
        placeSecond(h, metres: 80)                // the next house along
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        let run = try #require(store.runID)
        let stops = h.route.sortedStops
        h.clock += 300
        store.siteEntered(id(stops[0]), at: h.clock)
        h.clock += 900
        store.completeShownStop()                 // still inside the first area
        #expect(store.departures.isEmpty)
        #expect(sites.ids == [id(stops[1])])
        // Working the second stop, then leaving both areas at once: that's
        // when they left the second, not the first.
        h.clock += 1200
        store.siteExited(id(stops[0]), at: h.clock)
        store.siteExited(id(stops[1]), at: h.clock)
        #expect(ServiceLog.runRecord(run: run, stop: stops[0].id, in: h.context)?.leftAt == nil)
        #expect(store.site.leftAt == h.clock)     // the second stop's own departure is kept
    }

    @Test func areasOverlapUnderTwiceTheRadius() throws {
        let h = try Harness()
        pin(h)
        placeSecond(h, metres: 2 * SiteMonitor.radius - 10)
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(store.departures.isEmpty)

        let apart = try Harness()
        pin(apart)
        placeSecond(apart, metres: 2 * SiteMonitor.radius + 10)
        let other = apart.makeStore()
        other.start(apart.route)
        other.completeShownStop()
        #expect(other.departures.map(\.stopID) == [apart.route.sortedStops[0].id])
    }

    @Test func aPinMovedCloseStopsTheWait() throws {
        let h = try Harness()
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        let stops = h.route.sortedStops
        store.completeShownStop()
        #expect(store.departures.map(\.stopID) == [stops[0].id])
        // The second stop's pin corrected on another device, next door to the first.
        placeSecond(h, metres: 50)
        try h.context.save()
        #expect(store.departures.isEmpty)
        #expect(sites.ids == [id(stops[1])])
    }

    @Test func completingTheNextStopEndsTheWaitForTheLastOnesDeparture() throws {
        let h = try Harness()
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        let run = try #require(store.runID)
        let stops = h.route.sortedStops
        h.clock += 600
        store.completeShownStop()                 // the first stop's exit never came
        h.clock += 900
        store.completeShownStop()
        // Only the stop just completed is awaited: they were at the second
        // stop, so they'd left the first before it.
        #expect(store.departures.map(\.stopID) == [stops[1].id])
        #expect(sites.ids == [id(stops[1]), id(stops[2])])
        store.siteExited(id(stops[0]), at: h.clock + 60)
        #expect(ServiceLog.runRecord(run: run, stop: stops[0].id, in: h.context)?.leftAt == nil)
        // Below Trigger at the third stop: they were there too.
        h.clock += 600
        _ = store.passCurrentStop(expecting: stops[2].id)
        #expect(store.departures.isEmpty)
        store.siteExited(id(stops[1]), at: h.clock + 60)
        #expect(ServiceLog.runRecord(run: run, stop: stops[1].id, in: h.context)?.leftAt == nil)
    }

    @Test func comingIntoTheNextStopsAreaEndsTheWaitEvenWhenTheAreasDontOverlap() throws {
        // iOS reports an exit only some way past an area's edge: 300 m apart,
        // the crew can be at the second stop while still "in" the first's.
        let h = try Harness()
        pin(h)
        placeSecond(h, metres: 300)
        let store = h.makeStore()
        store.start(h.route)
        let run = try #require(store.runID)
        let stops = h.route.sortedStops
        h.clock += 600
        store.completeShownStop()
        #expect(store.departures.map(\.stopID) == [stops[0].id])
        h.clock += 120
        store.siteEntered(id(stops[1]), at: h.clock)
        #expect(store.departures.isEmpty)
        store.siteExited(id(stops[0]), at: h.clock + 900)
        #expect(ServiceLog.runRecord(run: run, stop: stops[0].id, in: h.context)?.leftAt == nil)
    }

    @Test func completingAStopSeenLeavingEndsTheWaitForTheLastOne() throws {
        // The second stop awaits nothing itself (its exit was seen): only the
        // clear on completing keeps the first stop's late exit off its record.
        let h = try Harness()
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let run = try #require(store.runID)
        let stops = h.route.sortedStops
        h.clock += 600
        store.completeShownStop()
        #expect(store.departures.map(\.stopID) == [stops[0].id])
        // Reported as having gone out of the second stop's area with no entry
        // first (no entry, so the first's wait isn't ended by an arrival).
        h.clock += 600
        store.siteExited(id(stops[1]), at: h.clock)
        h.clock += 60
        store.completeShownStop()
        #expect(store.departures.isEmpty)
        store.siteExited(id(stops[0]), at: h.clock + 60)
        #expect(ServiceLog.runRecord(run: run, stop: stops[0].id, in: h.context)?.leftAt == nil)
    }

    @Test func severalDeparturesSavedByAnOlderVersionAreCutToTheNewest() throws {
        let h = try Harness(stopCount: 1)
        let run = UUID()
        let saved = (0..<3).map { i in
            PendingDeparture(runID: run, stopID: UUID(), completedAt: h.clock - Double(300 * (3 - i)),
                             latitude: 43 + Double(i) / 100, longitude: -79)
        }
        SiteDepartures.save(saved, to: h.defaults)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.validate()
        #expect(store.departures == [saved[2]])
        #expect(sites.ids == [saved[2].stopID.uuidString])
    }

    @Test func nothingIsWatchedOrRemovedWhileTheRouteWaitsToBeRestored() throws {
        let h = try Harness()
        pin(h)
        h.makeClosedAppStore().start(h.route)
        struct Unreadable: Error {}
        let sites = FakeSiteWatching()
        _ = h.makeStore(sites: sites, fetchRoutes: { _ in throw Unreadable() })
        #expect(sites.watched.isEmpty)
    }

    @Test func aMovedPinMovesTheArea() throws {
        let h = try Harness()
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        let stop = h.route.sortedStops[0]
        stop.latitude = 44.5            // corrected on another device, say
        try h.context.save()
        #expect(sites.watched.last?.first { $0.id == id(stop) }?.latitude == 44.5)
    }

    @Test func aStopChangedWhileClosedHasNoTimesAfterARelaunch() throws {
        let h = try Harness()
        pin(h)
        let before = h.makeClosedAppStore()
        before.start(h.route)
        let first = h.route.sortedStops[0]
        before.siteEntered(id(first), at: h.clock + 400)
        h.context.delete(first)
        try h.context.save()
        let relaunched = h.makeStore()
        #expect(relaunched.currentStopID != first.id)
        // The first client's arrival mustn't land on the next client's record.
        #expect(relaunched.site == SiteTimes())
    }

    @Test func endRouteStopsWatchingTheCurrentStop() throws {
        let h = try Harness()
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        store.end()
        #expect(sites.watched.last == [])
    }

    @Test func aRelaunchDropsExpiredDepartures() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        store.end()
        h.clock += SiteDepartures.window + 1
        let sites = FakeSiteWatching()
        let relaunched = h.makeStore(sites: sites)
        #expect(relaunched.departures.isEmpty)
        #expect(sites.watched.last == [])
    }

    @Test func aDepartureFromBeforeTheCompletionIsntTaken() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let run = try #require(store.runID)
        let stop = h.route.sortedStops[0]
        h.clock += 600
        store.completeShownStop()
        // Reported late: the exit was before Complete, so it isn't leaving afterwards.
        store.siteExited(id(stop), at: h.clock - 30)
        #expect(try #require(ServiceLog.runRecord(run: run, stop: stop.id, in: h.context)).leftAt == nil)
    }

    @Test func onlyAreasGoneOrMovedAreReplaced() {
        let a = SiteArea(id: "a", latitude: 43, longitude: -79)
        let b = SiteArea(id: "b", latitude: 44, longitude: -79)
        let movedB = SiteArea(id: "b", latitude: 44.001, longitude: -79)
        let c = SiteArea(id: "c", latitude: 45, longitude: -79)
        let plan = SiteArea.plan(placed: [a, b], wanted: [a, movedB, c])
        #expect(plan.stop == ["b"])
        #expect(plan.place == [movedB, c])
        let same = SiteArea.plan(placed: [a, b], wanted: [b, a])
        #expect(same.stop.isEmpty && same.place.isEmpty)
    }

    @Test func eraseAllForgetsWaitingDepartures() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let sites = FakeSiteWatching()
        let store = h.makeStore(sites: sites)
        store.start(h.route)
        store.completeShownStop()
        store.eraseAll()
        #expect(store.departures.isEmpty)
        #expect(h.defaults.data(forKey: SiteDepartures.key) == nil)
        #expect(sites.ids.isEmpty)
    }

    // MARK: - The report

    @Test func theReportSaysWhatGPSSawAndWhatItDidnt() {
        let zone = TimeZone(identifier: "America/New_York") ?? .current
        let english = Locale(identifier: "en_US")
        func line(_ record: ServiceRecord) -> String? {
            ProofOfService.siteTimes(of: record, timeZone: zone, locale: english)?
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let at = { (h: Int, m: Int) in
            calendar.date(from: DateComponents(year: 2027, month: 1, day: 14, hour: h, minute: m)) ?? .distantPast
        }
        let record = ServiceRecord(operatorID: "op", sourceKey: "k", source: .route)
        #expect(line(record) == nil)
        record.arrivedAt = at(4, 58)
        record.leftAt = at(5, 24)
        #expect(line(record) == "Arrived 4:58 AM · Left 5:24 AM · 26 min on site (GPS, within about 100 m)")
        record.arrivedAt = nil
        #expect(line(record) == "Arrival not caught · Left 5:24 AM (GPS, within about 100 m)")
        record.arrivedAt = at(4, 58)
        record.leftAt = nil
        #expect(line(record) == "Arrived 4:58 AM · Departure not caught (GPS, within about 100 m)")
        let lines = ProofOfService.lines(of: ProofOfService.Visit(record: record, photos: []), placeAddress: "",
                                         timeZone: zone, locale: english)
        #expect(lines[1].hasPrefix("Arrived"))
    }
}
