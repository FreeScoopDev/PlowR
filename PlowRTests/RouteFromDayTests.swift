import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Schedule's Create Route: the "Route Created" alert offers Start Route
/// only for today's route with nothing running, and starts the run the
/// route's page would.
@MainActor
struct RouteFromDayTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: 12, hour: 9)) ?? .distantPast
    }

    // MARK: - When Start Route is offered

    @Test func startIsOfferedForTodaysRouteWithNothingRunning() {
        let lateToday = now.addingTimeInterval(12 * 3_600)
        #expect(RouteFromDay.offersStart(day: lateToday, now: now, routeRunning: false, stopsToRun: 3,
                                         calendar: calendar))
    }

    @Test func startIsNotOfferedForAnotherDay() {
        let tomorrow = now.addingTimeInterval(86_400)
        let yesterday = now.addingTimeInterval(-86_400)
        #expect(!RouteFromDay.offersStart(day: tomorrow, now: now, routeRunning: false, stopsToRun: 3,
                                          calendar: calendar))
        #expect(!RouteFromDay.offersStart(day: yesterday, now: now, routeRunning: false, stopsToRun: 3,
                                          calendar: calendar))
    }

    @Test func startIsNotOfferedWhileARouteIsRunning() {
        #expect(!RouteFromDay.offersStart(day: now, now: now, routeRunning: true, stopsToRun: 3,
                                          calendar: calendar))
    }

    @Test func startIsNotOfferedWithNoStopLeftToRunToday() {
        #expect(!RouteFromDay.offersStart(day: now, now: now, routeRunning: false, stopsToRun: 0,
                                          calendar: calendar))
    }

    // MARK: - The run it starts

    @Test func theRunLeavesOutStopsBelowTriggerTodayAsTheRoutePageDoes() throws {
        let h = try Harness(stopCount: 3)
        let stops = h.route.sortedStops
        let marked = h.clients[1].id.uuidString
        TriggerChecks.mark(clientID: marked, clientName: "Client 1", places: [marked], on: now,
                           operatorID: "op", in: h.context, now: now, calendar: calendar)
        let checks = try h.context.fetch(FetchDescriptor<TriggerCheck>())

        let run = TodaysRun.opening(h.route, on: now, checks: checks, calendar: calendar)
        #expect(run.routeStops == stops.map(\.id))
        #expect(run.skippedOnRoute == [stops[1].id])
        #expect(run.stops == [stops[0].id, stops[2].id])

        // A mark for another day leaves the whole route in.
        let tomorrow = TodaysRun.opening(h.route, on: now.addingTimeInterval(86_400), checks: checks,
                                         calendar: calendar)
        #expect(tomorrow.skippedOnRoute.isEmpty)
        #expect(tomorrow.stops.count == 3)
    }
}
