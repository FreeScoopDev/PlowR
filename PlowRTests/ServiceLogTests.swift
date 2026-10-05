//
//  ServiceLogTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The Service Log: one record each time work is done. Finishing a stop used
/// to leave only the client's running totals, and a stop's recorded services
/// were wiped the next time its route started.
@MainActor
struct ServiceLogTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func records(_ context: ModelContext) throws -> [ServiceRecord] {
        try context.fetch(FetchDescriptor<ServiceRecord>())
    }

    // MARK: - Route stops

    @Test func completingAStopRecordsTheWork() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let started = h.clock
        h.clock = started.addingTimeInterval(12 * 60)
        store.completeShownStop()

        let record = try #require(try records(h.context).first)
        #expect(try records(h.context).count == 1)
        #expect(record.source == .route)
        #expect(record.clientID == h.clients[0].id.uuidString)
        #expect(record.propertyID == h.clients[0].id.uuidString)
        #expect(record.clientName == "Client 0")
        #expect(record.propertyAddress == "0 Main St")
        #expect(record.startedAt == started)
        #expect(record.performedAt == h.clock)
        #expect(record.minutes == 12)
        #expect(record.routeID == h.route.id.uuidString)
        #expect(record.routeName == "Tuesday")
        #expect(record.stopID == stop.id.uuidString)
        #expect(record.operatorID == "op")
        #expect(record.isBillable)
        #expect(ServiceLog.isUnbilled(record, in: h.context))
    }

    // The services ticked on the stop go into the record, priced as Record
    // Services prices them: a per-square-foot service over the whole property.
    @Test func servicesRecordedOnTheStopArePricedForTheProperty() throws {
        let h = try Harness(stopCount: 1)
        let zone = PropertyZone(label: "Drive")
        zone.areaSquareFeet = 1_000
        h.context.insert(zone)
        zone.client = h.clients[0]
        let salt = ServiceItem(name: "Salt", category: "snow", unitType: "perSqFt", pricePerUnit: 0.05,
                               operatorID: "op", sortOrder: 2)
        let plow = ServiceItem(name: "Clear", category: "snow", unitType: "flat", pricePerUnit: 40,
                               operatorID: "op", sortOrder: 1)
        [salt, plow].forEach { h.context.insert($0) }
        try h.context.save()

        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        stop.completedServiceIDs = [salt.id.uuidString, UUID().uuidString, plow.id.uuidString]
        stop.completedNotes = "Gate was locked"
        store.completeShownStop()

        let record = try #require(try records(h.context).first)
        // Catalog order; a service no longer in the catalog is left out.
        #expect(record.lines.map(\.name) == ["Clear", "Salt"])
        #expect(record.lines.map(\.price) == [40, 50])
        #expect(record.notes == "Gate was locked")
    }

    // Siri and the screen completing the same stop, or a double tap, must
    // not make two records. (The store's own guard stops the second call.)
    @Test func aDoubleTapOnCompleteMakesOneRecord() throws {
        let h = try Harness(stopCount: 1)
        let store = h.makeStore()
        store.start(h.route)
        let stopID = try #require(store.currentStopID)
        store.completeCurrentStop(expecting: stopID)
        store.completeCurrentStop(expecting: stopID)
        #expect(try records(h.context).count == 1)
    }

    // Recording the same stop again on the same run updates its record, and
    // the latest times and services win.
    @Test func recordingAStopAgainUpdatesItsRecord() throws {
        let h = try Harness(stopCount: 1)
        let mowing = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 45, operatorID: "op")
        h.context.insert(mowing)
        let stop = try #require(h.route.sortedStops.first)
        let run = UUID()
        ServiceLog.recordStop(stop, of: h.client, run: run, operatorID: "op", startedAt: h.clock,
                              finishedAt: h.clock.addingTimeInterval(60), minutes: 1, in: h.context)
        stop.completedServiceIDs = [mowing.id.uuidString]
        let later = h.clock.addingTimeInterval(600)
        ServiceLog.recordStop(stop, of: h.client, run: run, operatorID: "op", startedAt: h.clock,
                              finishedAt: later, minutes: 10, in: h.context)
        let all = try records(h.context)
        #expect(all.count == 1)
        #expect(all.first?.performedAt == later)
        #expect(all.first?.minutes == 10)
        #expect(all.first?.lines.map(\.name) == ["Mowing"])
    }

    // Two devices that each recorded the same work before syncing: every
    // device must go on updating the same one, the oldest.
    @Test func theOldestRecordForAKeyIsTheOneUsed() throws {
        let h = try Harness(stopCount: 1)
        let newer = ServiceRecord(operatorID: "op", sourceKey: "visit:x", source: .visit)
        newer.createdAt = h.clock
        let older = ServiceRecord(operatorID: "op", sourceKey: "visit:x", source: .visit)
        older.createdAt = h.clock.addingTimeInterval(-60)
        h.context.insert(newer)
        h.context.insert(older)
        #expect(ServiceLog.record(forKey: "visit:x", in: h.context)?.id == older.id)
    }

    // A checkpoint saved by the version before runs existed: the route comes
    // back with a run, and its stops are still logged.
    @Test func aCheckpointFromBeforeRunsStillLogsStops() throws {
        let h = try Harness(stopCount: 2)
        let old = ActiveRouteStore.Checkpoint(routeID: h.route.id, currentStopIndex: 0,
                                              currentStopID: h.route.sortedStops.first?.id,
                                              stopStartedAt: h.clock, stopChangedUnseen: nil, runID: nil,
                                              runStartedAt: nil)
        let data = try JSONEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("runID"))
        h.defaults.set(data, forKey: ActiveRouteStore.checkpointKey)

        let store = h.makeStore()
        #expect(store.isActive)
        #expect(store.runID != nil)
        #expect(store.runStartedAt == h.clock)
        store.completeShownStop()
        #expect(try records(h.context).count == 1)
    }

    // Running the route again next week adds records; last week's stay.
    @Test func eachRunOfARouteHasItsOwnRecords() throws {
        let h = try Harness(stopCount: 1)
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        let firstRun = try #require(try records(h.context).first)
        let firstTime = firstRun.performedAt
        store.end()

        h.clock = h.clock.addingTimeInterval(7 * 86_400)
        store.start(h.route)
        store.completeShownStop()
        let all = try records(h.context)
        #expect(all.count == 2)
        #expect(Set(all.map(\.performedAt)) == [firstTime, h.clock])
    }

    // A relaunch mid-route is the same run: a stop's record written after it
    // must be the one its services were recorded against, not a second one.
    @Test func aRelaunchKeepsTheRun() throws {
        let h = try Harness()
        let before = h.makeClosedAppStore()
        before.start(h.route)
        let run = try #require(before.runID)
        let after = h.makeStore()
        #expect(after.runID == run)
    }

    @Test func endingARouteEndsTheRun() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        #expect(store.runID != nil)
        store.end()
        #expect(store.runID == nil)
    }

    // Comped work never goes on a bill, and that is decided when it's done.
    @Test func aCompedClientsWorkIsNotBillable() throws {
        let h = try Harness(stopCount: 1)
        h.clients[0].isComped = true
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        store.completeShownStop()
        let record = try #require(try records(h.context).first)
        #expect(!record.isBillable)
        #expect(!ServiceLog.isUnbilled(record, in: h.context))

        // Stopping the comp later doesn't make past work billable.
        h.clients[0].isComped = false
        let run = try #require(store.runID)
        ServiceLog.recordStop(stop, of: h.clients[0], run: run, operatorID: "op",
                              startedAt: h.clock, finishedAt: h.clock, minutes: 0, in: h.context)
        #expect(try records(h.context).count == 1)
        #expect(!record.isBillable)
    }

    @Test func aCustomStopHasNoRecord() throws {
        let h = try Harness(stopCount: 0)
        let custom = RouteStop(order: 0, customName: "Fuel up")
        custom.route = h.route
        h.context.insert(custom)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(try records(h.context).isEmpty)
    }

    // MARK: - A stop that is the day's visit

    private func scheduleVisit(_ h: Harness, _ client: Client, at date: Date) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: client.id.uuidString, clientName: client.name,
                                   clientAddress: client.address, scheduledDate: date)
        h.context.insert(visit)
        return visit
    }

    // Joe's call: finishing a stop completes the client's visit that day when
    // it's their only one, and the two are one record. The visit used to
    // stay due, and ticking it off later would have logged the work twice.
    @Test func completingAStopCompletesTheClientsOnlyVisitThatDay() throws {
        let h = try Harness(stopCount: 1)
        let visit = scheduleVisit(h, h.client, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        h.clock = h.clock.addingTimeInterval(15 * 60)
        store.completeShownStop()

        #expect(visit.status == .completed)
        #expect(visit.completedAt == h.clock)
        let all = try records(h.context)
        #expect(all.count == 1)
        #expect(all.first?.visitID == visit.id.uuidString)
        #expect(all.first?.sourceKey == ServiceLog.visitKey(visit.id))
        #expect(all.first?.source == .route)
        #expect(all.first?.minutes == 15)
    }

    // Ticked off in the Schedule first, then run on a route: still one record,
    // now with the route's times.
    @Test func aVisitDoneInTheScheduleThenOnARouteIsOneRecord() throws {
        let h = try Harness(stopCount: 1)
        let visit = scheduleVisit(h, h.client, at: h.clock)
        ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        h.clock = h.clock.addingTimeInterval(20 * 60)
        store.completeShownStop()

        let all = try records(h.context)
        #expect(all.count == 1)
        #expect(all.first?.visitID == visit.id.uuidString)
        #expect(all.first?.minutes == 20)
        #expect(all.first?.routeName == "Tuesday")
    }

    // Two visits that day: which one was it? Neither is touched.
    @Test func twoVisitsThatDayAreLeftAlone() throws {
        let h = try Harness(stopCount: 1)
        let first = scheduleVisit(h, h.client, at: h.clock)
        let second = scheduleVisit(h, h.client, at: h.clock.addingTimeInterval(60))
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()

        #expect(first.status == .scheduled)
        #expect(second.status == .scheduled)
        let all = try records(h.context)
        #expect(all.count == 1)
        #expect(all.first?.visitID == "")
    }

    // A visit on another day, or another client's, isn't this stop's.
    @Test func anotherDaysOrClientsVisitIsNotTouched() throws {
        let h = try Harness(stopCount: 2)
        let nextWeek = scheduleVisit(h, h.clients[0], at: h.clock.addingTimeInterval(7 * 86_400))
        let someoneElse = scheduleVisit(h, h.clients[1], at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(nextWeek.status == .scheduled)
        #expect(someoneElse.status == .scheduled)
    }

    // A second pass the same day (a storm) is its own work, not an overwrite
    // of the first pass's record.
    @Test func aSecondRunTheSameDayIsItsOwnRecord() throws {
        let h = try Harness(stopCount: 1)
        _ = scheduleVisit(h, h.client, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        store.end()
        h.clock = h.clock.addingTimeInterval(60)
        store.start(h.route)
        store.completeShownStop()

        let all = try records(h.context)
        #expect(all.count == 2)
        #expect(all.filter { !$0.visitID.isEmpty }.count == 1)
    }

    // A repeating visit completed from a route continues its series, as it
    // does from the Schedule.
    @Test func aRepeatingVisitCompletedOnARouteContinuesItsSeries() throws {
        let h = try Harness(stopCount: 1)
        let visit = scheduleVisit(h, h.client, at: h.clock)
        visit.isRecurring = true
        visit.recurrenceType = .weekly
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        let visits = try h.context.fetch(FetchDescriptor<ScheduledVisit>())
        #expect(visits.count == 2)
        #expect(visits.filter { $0.status == .scheduled }.count == 1)
    }

    // MARK: - Scheduled visits

    @MainActor
    final class Visits {
        let container: ModelContainer
        let context: ModelContext
        let client: Client
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            container = try ModelContainer(
                for: Schema(PlowRApp.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
            context = container.mainContext
            client = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
            context.insert(client)
            try context.save()
        }

        func visit(hoursFromNow hours: Double, for client: Client? = nil) -> ScheduledVisit {
            let client = client ?? self.client
            let visit = ScheduledVisit(operatorID: "op", clientID: client.id.uuidString, clientName: client.name,
                                       clientAddress: client.address,
                                       scheduledDate: now.addingTimeInterval(hours * 3_600))
            context.insert(visit)
            return visit
        }

        func all() throws -> [ScheduledVisit] { try context.fetch(FetchDescriptor<ScheduledVisit>()) }
    }

    @Test func completingAVisitRecordsTheWork() throws {
        let v = try Visits()
        let mowing = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 45, operatorID: "op")
        v.context.insert(mowing)
        let visit = v.visit(hoursFromNow: -20)
        visit.expectedServiceIDs = [mowing.id.uuidString]

        let record = try #require(ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now))
        #expect(visit.status == .completed)
        #expect(visit.completedAt == v.now)
        #expect(record.source == .visit)
        #expect(record.visitID == visit.id.uuidString)
        #expect(record.clientID == v.client.id.uuidString)
        #expect(record.propertyID == v.client.id.uuidString)
        #expect(record.propertyAddress == "1 Main St")
        #expect(record.lines.map(\.name) == ["Mowing"])
        #expect(record.lines.map(\.price) == [45])
        // Ticked off the next day: dated when it was due.
        #expect(record.performedAt == visit.scheduledDate)
        #expect(record.isBillable)
    }

    // Done ahead of time: dated when it was marked done.
    @Test func aVisitCompletedEarlyIsDatedNow() throws {
        let v = try Visits()
        let visit = v.visit(hoursFromNow: 5)
        let record = try #require(ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now))
        #expect(record.performedAt == v.now)
    }

    @Test func anAfterHoursVisitIsPricedWithItsMultiplier() throws {
        let v = try Visits()
        let clear = ServiceItem(name: "Clear", category: "snow", unitType: "flat", pricePerUnit: 40, operatorID: "op")
        v.context.insert(clear)
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [clear.id.uuidString]
        visit.isAfterHours = true
        visit.afterHoursMultiplier = 1.5
        let record = try #require(ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now))
        #expect(record.lines.map(\.price) == [60])
    }

    @Test func completingAVisitTwiceMakesOneRecord() throws {
        let v = try Visits()
        let visit = v.visit(hoursFromNow: -1)
        ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now)
        ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now)
        #expect(try v.context.fetch(FetchDescriptor<ServiceRecord>()).count == 1)
    }

    // A visit with no client on file is still completed, with no record:
    // there's no one to put it against.
    @Test func aVisitWithoutAClientIsCompletedWithoutARecord() throws {
        let v = try Visits()
        let visit = ScheduledVisit(operatorID: "op", clientID: "", clientName: "Walk-in", clientAddress: "",
                                   scheduledDate: v.now)
        v.context.insert(visit)
        #expect(ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now) == nil)
        #expect(visit.status == .completed)
        #expect(try v.context.fetch(FetchDescriptor<ServiceRecord>()).isEmpty)
    }

    // Completing still continues a repeating series, as it did from the Schedule.
    @Test func completingARepeatingVisitStillSchedulesTheNext() throws {
        let v = try Visits()
        let visit = v.visit(hoursFromNow: -1)
        visit.isRecurring = true
        visit.recurrenceType = .weekly
        visit.seriesID = UUID().uuidString
        ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now)
        let next = try v.all().filter { $0.id != visit.id }
        #expect(next.count == 1)
        #expect(next.first?.status == .scheduled)
    }

    @Test func aClientsRecordsAreNewestFirst() throws {
        let v = try Visits()
        let older = v.visit(hoursFromNow: -48)
        let newer = v.visit(hoursFromNow: -2)
        ServiceLog.complete(older, among: try v.all(), in: v.context, now: v.now)
        ServiceLog.complete(newer, among: try v.all(), in: v.context, now: v.now)
        let dates = ServiceLog.records(ofClient: v.client.id.uuidString, in: v.context).map(\.performedAt)
        #expect(dates == [newer.scheduledDate, older.scheduledDate])
    }

    // MARK: - Pricing

    @Test func propertyPriceAppliesTheMultiplierToTheWholeProperty() {
        let zones = [InvoiceLines.Zone(label: "A", areaSquareFeet: 1_000)]
        #expect(InvoiceLines.propertyPrice(unitType: "perSqFt", pricePerUnit: 0.05, zones: zones, multiplier: 1.5) == 75)
        #expect(InvoiceLines.propertyPrice(unitType: "flat", pricePerUnit: 40, zones: zones, multiplier: 1.5) == 60)
        #expect(InvoiceLines.propertyPrice(unitType: "flat", pricePerUnit: 40, zones: zones) == 40)
    }
}
