import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Can't Service: a stop skipped with a reason. The route moves on with no
/// visit, time, services or Service Log record, and the stop keeps the
/// reason until the route's next run.
@MainActor
struct CantServiceTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func records(_ h: Harness) throws -> [ServiceRecord] {
        try h.context.fetch(FetchDescriptor<ServiceRecord>())
    }

    // MARK: - The store

    @Test func aSkipRecordsNothingAndKeepsTheReason() throws {
        let h = try Harness(stopCount: 2)
        let client = h.clients[0]
        let visit = ScheduledVisit(operatorID: "op", clientID: client.id.uuidString, clientName: client.name,
                                   clientAddress: client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        h.clock += 900                                   // 15 minutes at the stop
        #expect(store.skipCurrentStop(expecting: stops[0].id, reason: "Gate locked") == .advanced(nextStopIndex: 1))
        #expect(store.currentStopID == stops[1].id)
        // Nothing credited.
        #expect(stops[0].actualMinutes == 0)
        #expect(stops[0].completedServiceIDs.isEmpty)
        #expect(client.totalVisits == 0)
        #expect(client.totalServiceMinutes == 0)
        #expect(client.lastServiceDate == nil)
        #expect(try records(h).isEmpty)
        #expect(visit.status == .scheduled)
        #expect(visit.completedAt == nil)
        // The reason and when, on the stop skipped only.
        #expect(stops[0].cantServiceReason == "Gate locked")
        #expect(stops[0].cantServiceAt == h.clock)
        #expect(stops[1].cantServiceReason.isEmpty)
        #expect(stops[1].cantServiceAt == nil)
    }

    @Test func skippingTheLastStopFinishesTheRoute() throws {
        let h = try Harness(stopCount: 1)
        let store = h.makeStore()
        store.start(h.route)
        let only = h.route.sortedStops[0]
        #expect(store.skipCurrentStop(expecting: only.id, reason: "Client cancelled") == .finishedLastStop)
        #expect(store.allStopsDone)
        #expect(only.cantServiceReason == "Client cancelled")
        let skippedAt = only.cantServiceAt
        // Asked again once it's behind: nothing is written over it.
        h.clock += 60
        #expect(store.skipCurrentStop(expecting: only.id, reason: "Other") == .allStopsAlreadyDone)
        #expect(only.cantServiceReason == "Client cancelled" && only.cantServiceAt == skippedAt)
        #expect(only.actualMinutes == 0)
        #expect(h.clients[0].totalVisits == 0)
        #expect(try records(h).isEmpty)
    }

    // The client at the next stop cancels by phone while the crew is still
    // at the one just done: its departure is still caught afterwards.
    @Test func aSkipKeepsWatchingTheStopBeforeForItsDeparture() throws {
        let h = try Harness(stopCount: 3)
        for (i, stop) in h.route.sortedStops.enumerated() {
            stop.latitude = 43 + Double(i) / 100
            stop.longitude = -79
        }
        let store = h.makeStore()
        store.start(h.route)
        let run = try #require(store.runID)
        let stops = h.route.sortedStops
        h.clock += 900
        #expect(store.completeCurrentStop(expecting: stops[0].id) == .advanced(nextStopIndex: 1))
        let completed = h.clock
        h.clock += 60
        #expect(store.skipCurrentStop(expecting: stops[1].id, reason: "Client cancelled") == .advanced(nextStopIndex: 2))
        #expect(store.departures.map(\.stopID) == [stops[0].id])
        store.siteExited(stops[0].id.uuidString, at: completed + 120)
        #expect(ServiceLog.runRecord(run: run, stop: stops[0].id, in: h.context)?.leftAt == completed + 120)
    }

    // iCloud took the stop off the route meanwhile: the sheet's stop isn't
    // current, so nothing moves and no reason is written anywhere.
    @Test func aChangedStopWritesNothing() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        h.context.delete(stops[0])
        try h.context.save()
        #expect(store.currentStopID == stops[1].id)
        #expect(store.skipCurrentStop(expecting: stops[0].id, reason: "Gate locked") == .stopChanged)
        #expect(store.currentStopID == stops[1].id)
        for stop in h.route.sortedStops {
            #expect(stop.cantServiceReason.isEmpty)
            #expect(stop.cantServiceAt == nil)
        }
        // A stop that isn't current, though still on the route.
        #expect(store.skipCurrentStop(expecting: stops[2].id, reason: "Gate locked") == .stopChanged)
        #expect(stops[2].cantServiceReason.isEmpty)
        #expect(stops[2].cantServiceAt == nil)
    }

    // A double tap: the stop is behind, and its first reason and time stay.
    @Test func aSecondSkipOfTheSameStopChangesNothing() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        store.skipCurrentStop(expecting: stops[0].id, reason: "Gate locked")
        let skippedAt = stops[0].cantServiceAt
        h.clock += 60
        #expect(store.isBehindCurrentStop(stops[0].id))
        #expect(store.skipCurrentStop(expecting: stops[0].id, reason: "Other") != .advanced(nextStopIndex: 2))
        #expect(store.currentStopID == stops[1].id)
        #expect(stops[0].cantServiceReason == "Gate locked")
        #expect(stops[0].cantServiceAt == skippedAt)
        #expect(stops[1].cantServiceReason.isEmpty)
    }

    @Test func startingARunClearsTheLastRunsReasons() throws {
        let h = try Harness(stopCount: 2)
        for stop in h.route.sortedStops {
            stop.cantServiceReason = "Vehicle in the way"
            stop.cantServiceAt = h.clock
        }
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        for stop in h.route.sortedStops {
            #expect(stop.cantServiceReason.isEmpty)
            #expect(stop.cantServiceAt == nil)
        }
    }

    // A skip can't be undone, and ends the last completion's Undo.
    @Test func aSkipEndsTheChanceToUndo() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        store.completeShownStop()
        #expect(store.undoOffer?.stopID == stops[0].id)
        store.skipCurrentStop(expecting: stops[1].id, reason: "Gate locked")
        #expect(store.undoOffer == nil)
        #expect(store.undoLastCompletion(expecting: stops[0].id) == .nothingToUndo)
        #expect(store.undoLastCompletion(expecting: stops[1].id) == .nothingToUndo)
        #expect(store.currentStopID == stops[2].id)
        #expect(stops[1].cantServiceReason == "Gate locked")
    }

    // Saved at once, not left to autosave (Siri's way of working can see the
    // app suspended first): a context of its own reads only saved values.
    @Test func theReasonIsSavedAtOnce() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        h.clock += 300
        store.skipCurrentStop(expecting: stops[0].id, reason: "Unsafe conditions")
        let fresh = ModelContext(h.container)
        let saved = try fresh.fetch(FetchDescriptor<RouteStop>()).first { $0.id == stops[0].id }
        #expect(saved?.cantServiceReason == "Unsafe conditions")
        #expect(saved?.cantServiceAt == h.clock)
    }

    // Skipped, then the app was ended: the relaunched route is past the stop,
    // and the recap still shows its reason as this run's.
    @Test func theReasonSurvivesARelaunch() throws {
        let h = try Harness(stopCount: 3)
        let before = h.makeClosedAppStore()
        before.start(h.route)
        let stops = h.route.sortedStops
        h.clock += 300
        #expect(before.skipCurrentStop(expecting: stops[0].id, reason: "Unsafe conditions") == .advanced(nextStopIndex: 1))
        try h.context.save()
        h.clock += 600
        let relaunched = h.makeStore()
        #expect(relaunched.currentStopID == stops[1].id)
        #expect(stops[0].cantServiceReason == "Unsafe conditions")
        #expect(CantService.recapLine(reason: stops[0].cantServiceReason, at: stops[0].cantServiceAt,
                                      runStartedAt: relaunched.runStartedAt) == "Can't service: Unsafe conditions")
        // Nothing credited on the way through the relaunch either.
        #expect(stops[0].actualMinutes == 0)
        #expect(h.clients[0].totalVisits == 0)
    }

    // MARK: - The rules the screens share

    @Test func theReasonKept() {
        #expect(CantService.reason(preset: "Gate locked", note: "") == "Gate locked")
        #expect(CantService.reason(preset: "Gate locked", note: "  code changed \n") == "Gate locked: code changed")
        #expect(CantService.reason(preset: "Other", note: "Dog in the yard") == "Dog in the yard")
        #expect(CantService.reason(preset: "Other", note: "   ") == "Other")
        #expect(CantService.reason(preset: "Vehicle in the way", note: "blue truck") == "Vehicle in the way: blue truck")
        #expect(CantService.presets == ["Vehicle in the way", "Gate locked", "Client cancelled", "Unsafe conditions",
                                        "Other"])
    }

    @Test func theRecapShowsOnlyThisRunsReason() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(CantService.recapLine(reason: "Gate locked", at: start, runStartedAt: start) == "Can't service: Gate locked")
        #expect(CantService.recapLine(reason: "Gate locked", at: start + 60, runStartedAt: start)
                == "Can't service: Gate locked")
        // An older run's, or one with no time (an older build).
        #expect(CantService.recapLine(reason: "Gate locked", at: start - 1, runStartedAt: start) == nil)
        #expect(CantService.recapLine(reason: "Gate locked", at: nil, runStartedAt: start) == nil)
        #expect(CantService.recapLine(reason: "Gate locked", at: start, runStartedAt: nil) == nil)
        #expect(CantService.recapLine(reason: "", at: start, runStartedAt: start) == nil)
    }

    @Test func theRoutePageLine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Toronto"))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9)))
        #expect(CantService.routeLine(reason: "Gate locked", at: day, locale: Locale(identifier: "en_US"),
                                      calendar: calendar)
                == "Couldn't service Nov 10: Gate locked")
        #expect(CantService.routeLine(reason: "", at: day, calendar: calendar) == nil)
        #expect(CantService.routeLine(reason: "Gate locked", at: nil, calendar: calendar) == nil)
    }

    // Not beside recorded work: the rule Below Trigger uses too.
    @Test func notOfferedOnceWorkIsRecorded() {
        #expect(!CantService.isWorkRecorded(completedServiceIDs: [], hasRunRecord: false))
        #expect(CantService.isWorkRecorded(completedServiceIDs: ["mow"], hasRunRecord: false))
        #expect(CantService.isWorkRecorded(completedServiceIDs: [], hasRunRecord: true))
    }

    // MARK: - Where it can be reached

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // Only the route screen skips, through the store; never Siri, Control
    // Center, the widget or the Live Activity. Both rules share one helper.
    @Test func onlyTheRouteScreenSkips() throws {
        let screen = try Self.source("PlowR/Views/ActiveRoute/ActiveRouteView.swift")
        #expect(screen.contains("store.skipCurrentStop(expecting: stop.id, reason: reason)"))
        #expect(screen.contains("guard let client = client(for: stop), !isWorkRecorded(at: stop) else { return nil }"))
        #expect(screen.contains("if !isWorkRecorded(at: stop) {"))
        let paths = ["PlowR/Intents", "PlowRWidgets", "PlowR/Activity"]
        for folder in paths {
            let files = FileManager.default.enumerator(at: Self.root.appendingPathComponent(folder),
                                                       includingPropertiesForKeys: nil)
            var checked = 0
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                checked += 1
                let text = try String(contentsOf: url, encoding: .utf8)
                #expect(!text.contains("skipCurrentStop"), "\(url.lastPathComponent) skips a stop")
            }
            #expect(checked > 0, "\(folder) has no Swift files")
        }
    }
}
