import Foundation
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
        site.entered(at: start + 600, stopStartedAt: start)
        site.exited(at: start + 900)
        site.entered(at: start + 1000, stopStartedAt: start)     // back for the shovel
        #expect(site.arrivedAt == start + 600)
        #expect(site.leftAt == nil)                               // came back in: hadn't left
        site.exited(at: start + 1500)
        #expect(site.leftAt == start + 1500)
        #expect(!site.arrivalUnseen)
    }

    @Test func alreadyInsideWhenTheStopBeganHasNoArrival() {
        // iOS reporting a phone already in the area, just after it's placed.
        var site = SiteTimes()
        site.entered(at: start + SiteTimes.settleTime - 1, stopStartedAt: start)
        #expect(site.arrivedAt == nil && site.arrivalUnseen)
        // Out to the truck and back: still not an arrival.
        site.exited(at: start + 300)
        site.entered(at: start + 400, stopStartedAt: start)
        #expect(site.arrivedAt == nil)
        // At exactly the settle time it is one.
        var later = SiteTimes()
        later.entered(at: start + SiteTimes.settleTime, stopStartedAt: start)
        #expect(later.arrivedAt == start + SiteTimes.settleTime)
    }

    @Test func leavingWithoutBeingSeenToArriveIsNoArrival() {
        var site = SiteTimes()
        site.exited(at: start + 300)
        #expect(site.arrivalUnseen && site.arrivedAt == nil && site.leftAt == start + 300)
        site.entered(at: start + 900, stopStartedAt: start)
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
        #expect(ServiceLog.runRecord(run: run, stop: stop.id, in: h.context)?.leftAt == nil)
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
        #expect(ServiceLog.runRecord(run: otherRun, stop: otherStop.id, in: second.context)?.leftAt == nil)
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
        before.configure(context: h.context)
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

    @Test func runningTheRouteAgainDropsItsStopsWaitingDepartures() throws {
        let h = try Harness(stopCount: 1)
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        store.end()
        #expect(store.departures.count == 1)
        store.start(h.route)
        // Otherwise leaving this run's first stop would count for last run's too.
        #expect(store.departures.isEmpty)
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
        #expect(line(record) == "Arrived 4:58 AM · Left 5:24 AM (GPS, within about 100 m)")
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
