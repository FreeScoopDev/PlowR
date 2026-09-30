//
//  RouteFactsTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// What the route list and a route's page say about a route: about how long
/// it takes, and when it last ran.
@MainActor
struct RouteFactsTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    @Test func estimateIsTheClientsAverageTimes() throws {
        let h = try Harness(stopCount: 3)
        h.clients[0].totalVisits = 2
        h.clients[0].totalServiceMinutes = 50          // average 25
        h.clients[1].totalVisits = 1
        h.clients[1].totalServiceMinutes = 40          // average 40
        // Client 2 has no history: not counted.
        let custom = RouteStop(order: 3, customName: "Fuel")
        #expect(RouteFacts.estimatedMinutes(of: h.route.sortedStops + [custom], clients: h.clients) == 65)
    }

    @Test(arguments: [(45, "45m"), (60, "1h"), (80, "1h 20m"), (0, "0m")])
    func durations(minutes: Int, text: String) {
        #expect(RouteFacts.duration(minutes) == text)
    }

    // A route's last run is its latest completed stop; records with no times
    // (saved from Record Services, never completed) and other routes' don't count.
    @Test func lastRunIsTheLatestCompletedStop() throws {
        let h = try Harness(stopCount: 1)
        func record(route: UUID, at date: Date, completed: Bool = true) -> ServiceRecord {
            let record = ServiceRecord(operatorID: "op", sourceKey: "stop:\(UUID())", source: .route)
            record.routeID = route.uuidString
            record.performedAt = date
            if completed { record.startedAt = date }
            return record
        }
        let other = UUID()
        let records = [
            record(route: h.route.id, at: h.clock.addingTimeInterval(-86_400)),
            record(route: h.route.id, at: h.clock),
            record(route: h.route.id, at: h.clock.addingTimeInterval(3_600), completed: false),
            record(route: other, at: h.clock.addingTimeInterval(7_200)),
        ]
        #expect(RouteFacts.lastRun(of: h.route.id, in: records) == h.clock)
        let all = RouteFacts.lastRuns(in: records)
        #expect(all[h.route.id.uuidString] == h.clock)
        #expect(all[other.uuidString] == h.clock.addingTimeInterval(7_200))
        #expect(RouteFacts.lastRun(of: UUID(), in: records) == nil)
    }

    @Test func lastRunReadsNaturally() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
        func ago(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }
        #expect(RouteFacts.lastRunText(now.addingTimeInterval(-3_600), now: now, calendar: calendar) == "Last run today")
        #expect(RouteFacts.lastRunText(ago(1), now: now, calendar: calendar) == "Last run yesterday")
        #expect(RouteFacts.lastRunText(ago(3), now: now, calendar: calendar) == "Last run 3 days ago")
        #expect(RouteFacts.lastRunText(ago(9), now: now, calendar: calendar).hasPrefix("Last run Sep"))
    }
}
