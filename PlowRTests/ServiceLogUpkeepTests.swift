//
//  ServiceLogUpkeepTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Keeping the Service Log whole: the same work recorded on two devices is
/// merged, and completed visits are marked as in the log.
@MainActor
struct ServiceLogUpkeepTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func records(_ h: Harness) throws -> [ServiceRecord] {
        try h.context.fetch(FetchDescriptor<ServiceRecord>())
    }

    private func visit(_ h: Harness, _ client: Client, _ status: VisitStatus, daysAgo: Double) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: client.id.uuidString, clientName: client.name,
                                   clientAddress: client.address,
                                   scheduledDate: h.clock.addingTimeInterval(-daysAgo * 86_400))
        visit.status = status
        if status == .completed { visit.completedAt = visit.scheduledDate.addingTimeInterval(3_600) }
        h.context.insert(visit)
        return visit
    }

    // MARK: - The visit's mark

    // Completing a visit, from the Schedule or on a route, marks it as in the
    // log: a later copy of completed visits into the log must skip it.
    @Test func completingAVisitMarksItLogged() throws {
        let h = try Harness(stopCount: 1)
        let fromSchedule = visit(h, h.client, .scheduled, daysAgo: 1)
        ServiceLog.complete(fromSchedule, among: [fromSchedule], in: h.context, now: h.clock)
        #expect(fromSchedule.serviceLogged)

        let onRoute = visit(h, h.client, .scheduled, daysAgo: 0)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(onRoute.serviceLogged)
    }

    // Recorded from the sheet, the record deleted, then the visit completed in
    // the Schedule: the mark doesn't stop the new record.
    @Test func aVisitWhoseRecordWasDeletedStillGetsOneWhenCompleted() throws {
        let h = try Harness(stopCount: 1)
        let visit = visit(h, h.client, .scheduled, daysAgo: 0)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let first = ServiceLog.saveRecording(StopRecording(services: [], zones: []), notes: "n",
                                             for: try #require(store.currentStop), of: h.client,
                                             run: try #require(store.runID), operatorID: "op",
                                             startedAt: h.clock, in: h.context)
        #expect(visit.serviceLogged)
        ServiceLog.deleteRecord(first, in: h.context)
        try h.context.save()
        let again = ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock)
        #expect(again != nil)
        #expect(try records(h).count == 1)
    }

    // MARK: - Merging

    private func copy(_ h: Harness, key: String = "visit:x", secondsAfter: TimeInterval) -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: key, source: .visit)
        record.createdAt = h.clock.addingTimeInterval(secondsAfter)
        return record
    }

    private func invoice(_ h: Harness, _ number: String) -> Proposal {
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = number
        h.context.insert(invoice)
        return invoice
    }

    private var aDayLater: TimeInterval { ServiceLog.mergeAfter + 60 }

    // Two devices recorded the same visit before syncing: one record stays,
    // the oldest, with what the other had that it lacked. (The newer copy is
    // inserted first, so insertion order can't stand in for age.)
    @Test func theSameWorkFromTwoDevicesIsMerged() throws {
        let h = try Harness(stopCount: 1)
        let newer = copy(h, secondsAfter: 5)
        newer.lines = [ServiceRecord.Line(serviceID: "s", name: "Clear", unitType: "flat", price: 40)]
        newer.startedAt = h.clock
        newer.minutes = 12
        newer.runID = "run"
        newer.routeName = "Tuesday"
        let photo = StopPhoto(operatorID: "op", clientID: "", routeID: "", isBefore: false, imageData: Data([1]))
        photo.recordID = newer.id.uuidString
        let older = copy(h, secondsAfter: 0)
        older.notes = "Gate code 1234"
        [newer, older].forEach { h.context.insert($0) }
        h.context.insert(photo)
        try h.context.save()

        #expect(ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater)) == 1)
        #expect(try records(h).map(\.id) == [older.id])
        #expect(older.notes == "Gate code 1234")
        #expect(older.lines.map(\.name) == ["Clear"])
        #expect(older.minutes == 12)
        #expect(older.runID == "run")
        #expect(older.routeName == "Tuesday")
        #expect(photo.recordID == older.id.uuidString)
    }

    // Before the day is out, a copy may still be written to on its device:
    // it's left for now.
    @Test func aFreshCopyIsLeftForADay() throws {
        let h = try Harness(stopCount: 1)
        [copy(h, secondsAfter: 5), copy(h, secondsAfter: 0)].forEach { h.context.insert($0) }
        #expect(ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(3_600)) == 0)
        #expect(try records(h).count == 2)
    }

    // The survivor takes an invoice only with the services that invoice
    // billed, so it still matches the bill.
    @Test func anAdoptedInvoiceBringsItsServices() throws {
        let h = try Harness(stopCount: 1)
        let bill = invoice(h, "INV-0060")
        let newer = copy(h, secondsAfter: 5)
        newer.lines = [ServiceRecord.Line(serviceID: "m", name: "Mowing", unitType: "flat", price: 45),
                       ServiceRecord.Line(serviceID: "", name: "Gate fix", unitType: "flat", price: 15)]
        newer.invoiceID = bill.id.uuidString
        let older = copy(h, secondsAfter: 0)
        older.lines = [ServiceRecord.Line(serviceID: "m", name: "Mowing", unitType: "flat", price: 45)]
        [newer, older].forEach { h.context.insert($0) }
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(older.invoiceID == bill.id.uuidString)
        #expect(older.lines.map(\.price) == [45, 15])
    }

    // The copy is on an invoice made ahead with no services: the survivor
    // takes the invoice and keeps the services it recorded.
    @Test func anInvoiceWithoutServicesDoesNotWipeTheSurvivors() throws {
        let h = try Harness(stopCount: 1)
        let ahead = invoice(h, "INV-0062")
        let newer = copy(h, secondsAfter: 5)
        newer.invoiceID = ahead.id.uuidString
        let older = copy(h, secondsAfter: 0)
        older.lines = [ServiceRecord.Line(serviceID: "m", name: "Mowing", unitType: "flat", price: 45)]
        [newer, older].forEach { h.context.insert($0) }
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(older.invoiceID == ahead.id.uuidString)
        #expect(older.lines.map(\.name) == ["Mowing"])
    }

    // The survivor is on an invoice with no services; the copy has what was
    // done: the survivor takes it, rather than it going with the copy.
    @Test func aSurvivorOnAnInvoiceWithoutServicesTakesTheCopys() throws {
        let h = try Harness(stopCount: 1)
        let ahead = invoice(h, "INV-0063")
        let newer = copy(h, secondsAfter: 5)
        newer.lines = [ServiceRecord.Line(serviceID: "m", name: "Mowing", unitType: "flat", price: 45),
                       ServiceRecord.Line(serviceID: "e", name: "Edging", unitType: "flat", price: 15)]
        newer.invoiceID = ahead.id.uuidString
        let older = copy(h, secondsAfter: 0)
        older.invoiceID = ahead.id.uuidString
        [newer, older].forEach { h.context.insert($0) }
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(try records(h).map(\.id) == [older.id])
        #expect(older.lines.map(\.name) == ["Mowing", "Edging"])
    }

    // Taking a route's times, it says it came from the route.
    @Test func takingARoutesTimesMakesItARouteRecord() throws {
        let h = try Harness(stopCount: 1)
        let newer = copy(h, secondsAfter: 5)
        newer.source = .route
        newer.startedAt = h.clock
        let older = copy(h, secondsAfter: 0)
        [newer, older].forEach { h.context.insert($0) }
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(older.source == .route)
    }

    // On two different invoices, it's billed twice for real: both stay.
    @Test func copiesOnDifferentInvoicesAreNotMerged() throws {
        let h = try Harness(stopCount: 1)
        let newer = copy(h, secondsAfter: 5)
        newer.invoiceID = invoice(h, "INV-A").id.uuidString
        let older = copy(h, secondsAfter: 0)
        older.invoiceID = invoice(h, "INV-B").id.uuidString
        [newer, older].forEach { h.context.insert($0) }
        #expect(ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater)) == 0)
        #expect(try records(h).count == 2)
    }

    // What the survivor already has, it keeps: its invoice and services, its
    // route and times, its notes.
    @Test func mergingKeepsWhatTheSurvivorHas() throws {
        let h = try Harness(stopCount: 1)
        let mine = invoice(h, "INV-0061")
        let newer = copy(h, secondsAfter: 5)
        newer.lines = [ServiceRecord.Line(serviceID: "b", name: "Theirs", unitType: "flat", price: 99)]
        newer.notes = "Theirs"
        newer.startedAt = h.clock.addingTimeInterval(100)
        newer.minutes = 50
        newer.runID = "their run"
        let older = copy(h, secondsAfter: 0)
        older.lines = [ServiceRecord.Line(serviceID: "a", name: "Mine", unitType: "flat", price: 10)]
        older.invoiceID = mine.id.uuidString
        older.notes = "Mine"
        older.startedAt = h.clock
        older.minutes = 5
        older.runID = "my run"
        [newer, older].forEach { h.context.insert($0) }
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(try records(h).map(\.id) == [older.id])
        #expect(older.lines.map(\.name) == ["Mine"])
        #expect(older.invoiceID == mine.id.uuidString)
        #expect(older.notes == "Mine")
        #expect(older.minutes == 5)
        #expect(older.runID == "my run")
    }

    // A visit ticked off in the office (its expected services) and done on
    // the route (what the crew recorded): the route's services are the work.
    @Test func aRoutesServicesWinOverAVisitsExpectedOnes() throws {
        let h = try Harness(stopCount: 1)
        let newer = copy(h, secondsAfter: 5)
        newer.lines = [ServiceRecord.Line(serviceID: "c", name: "Clear", unitType: "flat", price: 55)]
        newer.startedAt = h.clock
        let older = copy(h, secondsAfter: 0)
        older.lines = [ServiceRecord.Line(serviceID: "c", name: "Clear", unitType: "flat", price: 40)]
        [newer, older].forEach { h.context.insert($0) }
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(older.lines.map(\.price) == [55])
    }

    // Two copies made in the same instant: every device keeps the same one.
    @Test func aTieIsBrokenTheSameWayEverywhere() throws {
        let h = try Harness(stopCount: 1)
        let a = copy(h, secondsAfter: 0)
        let b = copy(h, secondsAfter: 0)
        [b, a].forEach { h.context.insert($0) }
        let expected = a.id.uuidString < b.id.uuidString ? a.id : b.id
        #expect(ServiceLog.record(forKey: "visit:x", in: h.context)?.id == expected)
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(try records(h).map(\.id) == [expected])
    }

    // Different work, and records without a key, are never merged.
    @Test func differentWorkIsNeverMerged() throws {
        let h = try Harness(stopCount: 1)
        for _ in 0..<2 {
            ServiceLog.logWork(StopRecording(services: [], zones: []), notes: "n", performedAt: h.clock, minutes: 0,
                               for: h.client, operatorID: "op", now: h.clock, in: h.context)
        }
        h.context.insert(copy(h, key: "visit:a", secondsAfter: 0))
        h.context.insert(copy(h, key: "visit:b", secondsAfter: 0))
        h.context.insert(copy(h, key: "", secondsAfter: 0))
        h.context.insert(copy(h, key: "", secondsAfter: 1))
        #expect(ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater)) == 0)
        #expect(try records(h).count == 6)
    }
}
