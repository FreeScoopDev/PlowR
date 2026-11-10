import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A stop's minutes count from GPS's arrival when it was caught, otherwise
/// from when the stop became current, and the record says which.
@MainActor
struct TimeFromArrivalTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - The pure rule

    @Test func countedFollowsTheArrivalOnlyWhenItBelongsToTheStop() {
        let finish = start + 1_800   // 30 min after the stop became current
        func counted(_ arrival: Date?) -> (minutes: Double, basis: StopMinutes.Basis) {
            StopMinutes.counted(startedAt: start, arrivedAt: arrival, finishedAt: finish)
        }
        // No arrival: today's rule.
        #expect(counted(nil).minutes == 30 && counted(nil).basis == .includesTravel)
        // Arrival inside: from it.
        #expect(counted(start + 600).minutes == 20 && counted(start + 600).basis == .fromArrival)
        // Before the stop became current, or after the completion: ignored.
        #expect(counted(start - 60).minutes == 30 && counted(start - 60).basis == .includesTravel)
        #expect(counted(finish + 60).minutes == 30 && counted(finish + 60).basis == .includesTravel)
        // Equal times: the edges are inside.
        #expect(counted(start).minutes == 30 && counted(start).basis == .fromArrival)
        #expect(counted(finish).minutes == 0 && counted(finish).basis == .fromArrival)
        // Never negative, even with a clock gone backwards.
        #expect(StopMinutes.counted(startedAt: finish, arrivedAt: nil, finishedAt: start).minutes == 0)
    }

    // MARK: - Completing through the store

    private func records(_ h: Harness) throws -> [ServiceRecord] {
        try h.context.fetch(FetchDescriptor<ServiceRecord>())
    }

    @Test func aCaughtArrivalCountsMinutesFromIt() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let began = try #require(store.stopStartedAt)
        h.clock += 600
        store.siteEntered(stop.id.uuidString, at: h.clock)      // drove for 10 min
        h.clock += 900                                          // 15 min there
        store.completeCurrentStop(expecting: stop.id)
        #expect(stop.actualMinutes == 15)
        let record = try #require(try records(h).first)
        #expect(abs(record.minutes - 15) < 0.001)
        #expect(record.startedAt == began && record.arrivedAt == began + 600)
        #expect(abs(h.clients[0].totalServiceMinutes - 15) < 0.001)
        #expect(ServiceLog.minutesBasis(of: record) == .fromArrival)
        // A departure afterwards doesn't recompute them.
        store.siteExited(stop.id.uuidString, at: h.clock + 300)
        #expect(abs(record.minutes - 15) < 0.001 && stop.actualMinutes == 15)
        #expect(abs(h.clients[0].totalServiceMinutes - 15) < 0.001)
    }

    @Test func noArrivalCountsMinutesAsBefore() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        h.clock += 1_500
        store.completeCurrentStop(expecting: stop.id)
        #expect(stop.actualMinutes == 25)
        let record = try #require(try records(h).first)
        #expect(abs(record.minutes - 25) < 0.001 && record.arrivedAt == nil)
        #expect(abs(h.clients[0].totalServiceMinutes - 25) < 0.001)
        #expect(ServiceLog.minutesBasis(of: record) == .includesTravel)
    }

    @Test func undoTakesBackTheArrivalBasedMinutes() throws {
        let h = try Harness(stopCount: 2)
        h.clients[0].totalServiceMinutes = 40
        h.clients[0].totalVisits = 2
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        h.clock += 600
        store.siteEntered(stop.id.uuidString, at: h.clock)
        h.clock += 480
        store.completeCurrentStop(expecting: stop.id)
        #expect(abs(h.clients[0].totalServiceMinutes - 48) < 0.001)
        h.clock += 10
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(abs(h.clients[0].totalServiceMinutes - 40) < 0.001 && h.clients[0].totalVisits == 2)
        #expect(stop.actualMinutes == 0)
    }

    // MARK: - The basis of a saved record

    private func record(source: ServiceRecordSource = .route, arrived: Date?, minutes: Double) -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: "stop:\(UUID().uuidString)", source: source)
        record.startedAt = start
        record.performedAt = start + 1_800
        record.arrivedAt = arrived
        record.minutes = minutes
        return record
    }

    @Test func minutesBasisIsDerivedFromTheRecord() {
        // Arrival-based: minutes match completion minus arrival (within a second).
        #expect(ServiceLog.minutesBasis(of: record(arrived: start + 600, minutes: 20)) == .fromArrival)
        #expect(ServiceLog.minutesBasis(of: record(arrived: start + 600, minutes: 20 + 0.9 / 60)) == .fromArrival)
        // Old-style: counted from the start, travel in.
        #expect(ServiceLog.minutesBasis(of: record(arrived: start + 600, minutes: 30)) == .includesTravel)
        #expect(ServiceLog.minutesBasis(of: record(arrived: nil, minutes: 30)) == .includesTravel)
        // Old-style where the two agree: no travel, so from arrival is true.
        #expect(ServiceLog.minutesBasis(of: record(arrived: start, minutes: 30)) == .fromArrival)
        // Edited by hand: no longer matches.
        #expect(ServiceLog.minutesBasis(of: record(arrived: start + 600, minutes: 45)) == .includesTravel)
        // Not a route stop's.
        #expect(ServiceLog.minutesBasis(of: record(source: .manual, arrived: nil, minutes: 30)) == nil)
        #expect(ServiceLog.minutesBasis(of: record(source: .visit, arrived: start + 600, minutes: 20)) == nil)
    }

    // MARK: - The report's wording

    @Test func theReportLineSaysWhichBasis() {
        let english = Locale(identifier: "en_US")
        let zone = TimeZone(identifier: "UTC") ?? .current
        func line(_ record: ServiceRecord) -> String {
            ProofOfService.times(of: record, timeZone: zone, locale: english)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(line(record(arrived: start + 600, minutes: 20)).hasSuffix(" · 20 min on site, from GPS arrival"))
        #expect(line(record(arrived: nil, minutes: 30)).hasSuffix(" · 30 min, including travel"))
        #expect(line(record(arrived: start + 600, minutes: 30)).hasSuffix(" · 30 min, including travel"))
        #expect(ProofOfService.note().contains("from GPS arrival") && ProofOfService.note().contains("includes the drive there") && !ProofOfService.note().contains("on site"))
    }
}
