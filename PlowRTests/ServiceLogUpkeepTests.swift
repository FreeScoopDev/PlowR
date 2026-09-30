//
//  ServiceLogUpkeepTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Keeping the Service Log whole: visits completed without a record get one,
/// once per visit, and the same work recorded on two devices is merged.
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

    // MARK: - Visits from before the log

    @Test func completedVisitsAreCopiedInAsBillingNotTracked() throws {
        let h = try Harness(stopCount: 2)
        let mowing = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 45, operatorID: "op")
        h.context.insert(mowing)
        let done = visit(h, h.clients[0], .completed, daysAgo: 10)
        done.expectedServiceIDs = [mowing.id.uuidString]
        let other = visit(h, h.clients[1], .completed, daysAgo: 3)
        let ahead = visit(h, h.clients[0], .scheduled, daysAgo: -2)
        let skipped = visit(h, h.clients[0], .skipped, daysAgo: 5)
        try h.context.save()

        #expect(ServiceLog.backfillCompletedVisits(in: h.context).made == 2)
        let all = try records(h)
        #expect(Set(all.map(\.visitID)) == [done.id.uuidString, other.id.uuidString])
        let first = try #require(all.first { $0.visitID == done.id.uuidString })
        #expect(first.source == .beforeLog)
        #expect(first.clientName == h.clients[0].name)
        #expect(first.performedAt == done.scheduledDate)
        #expect(first.lines.map(\.price) == [45])
        // Joe's call: never counted as owed.
        #expect(!ServiceLog.isUnbilled(first, in: h.context))
        #expect(ServiceLog.billingStatus(of: first, in: h.context) == .notTracked)
        #expect(done.serviceLogged && other.serviceLogged)
        #expect(!ahead.serviceLogged && !skipped.serviceLogged)
        #expect(ServiceLog.backfillCompletedVisits(in: h.context).made == 0)
    }

    // A job the user deleted isn't made again: not at the next launch, and
    // not by another device or a new phone, since the mark travels with the visit.
    @Test func aDeletedJobIsNeverMadeAgain() throws {
        let h = try Harness(stopCount: 1)
        let done = visit(h, h.client, .completed, daysAgo: 4)
        try h.context.save()
        ServiceLog.backfillCompletedVisits(in: h.context)
        let record = try #require(try records(h).first)
        ServiceLog.deleteRecord(record, in: h.context)
        try h.context.save()
        #expect(done.serviceLogged)
        #expect(ServiceLog.backfillCompletedVisits(in: h.context).made == 0)
        #expect(try records(h).isEmpty)
    }

    // A visit whose client hasn't arrived on this device yet waits.
    @Test func aVisitWithoutItsClientWaits() throws {
        let h = try Harness(stopCount: 1)
        let orphan = ScheduledVisit(operatorID: "op", clientID: UUID().uuidString, clientName: "Not here yet",
                                    clientAddress: "", scheduledDate: h.clock)
        orphan.status = .completed
        h.context.insert(orphan)
        try h.context.save()
        #expect(ServiceLog.backfillCompletedVisits(in: h.context).made == 0)
        #expect(!orphan.serviceLogged)
    }

    // A completed visit that already has a record (another device made it)
    // is only marked.
    @Test func aVisitThatHasARecordIsOnlyMarked() throws {
        let h = try Harness(stopCount: 1)
        let done = visit(h, h.client, .completed, daysAgo: 1)
        h.context.insert(ServiceRecord(operatorID: "op", sourceKey: ServiceLog.visitKey(done.id), source: .visit))
        try h.context.save()
        #expect(ServiceLog.backfillCompletedVisits(in: h.context).made == 0)
        #expect(done.serviceLogged)
        #expect(try records(h).count == 1)
    }

    // Invoiced for the visit (Schedule → Invoice): that's known, so it shows
    // as invoiced.
    @Test func aVisitInvoicedBeforeTheLogShowsAsInvoiced() throws {
        let h = try Harness(stopCount: 1)
        let invoiced = visit(h, h.client, .completed, daysAgo: 4)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0050"
        h.context.insert(invoice)
        invoiced.proposalID = invoice.id.uuidString
        try h.context.save()
        ServiceLog.backfillCompletedVisits(in: h.context)
        let record = try #require(try records(h).first)
        #expect(record.invoiceID == invoice.id.uuidString)
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .invoiced)
    }

    // A long history goes in passes: each handles at most a batch and saves,
    // and the passes together copy in all of it.
    @Test func aLongHistoryIsCopiedInPasses() throws {
        let h = try Harness(stopCount: 1)
        let count = 25
        for day in 0..<count { _ = visit(h, h.client, .completed, daysAgo: Double(day + 1)) }
        try h.context.save()
        var saves = 0
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: h.context,
                                                              queue: nil) { _ in saves += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        var passes: [Int] = []
        while case let pass = ServiceLog.backfillCompletedVisits(in: h.context, limit: 10), pass.handled > 0 {
            passes.append(pass.made)
        }
        #expect(passes == [10, 10, 5])
        #expect(saves == 3)
        #expect(try records(h).count == count)
    }

    // Visits of a client not on this device are left, and a pass with only
    // those to look at does nothing.
    @Test func onlyVisitsWithoutTheirClientMeansNothingToDo() throws {
        let h = try Harness(stopCount: 1)
        let orphan = ScheduledVisit(operatorID: "op", clientID: UUID().uuidString, clientName: "Gone",
                                    clientAddress: "", scheduledDate: h.clock)
        orphan.status = .completed
        h.context.insert(orphan)
        try h.context.save()
        #expect(ServiceLog.backfillCompletedVisits(in: h.context).handled == 0)
    }

    // The visit's invoice hadn't arrived from iCloud when the job was copied
    // in (or was made later on an older PlowR): it catches up.
    @Test func aCopiedJobCatchesUpWithItsVisitsInvoice() throws {
        let h = try Harness(stopCount: 1)
        let done = visit(h, h.client, .completed, daysAgo: 4)
        let invoiceID = UUID()
        done.proposalID = invoiceID.uuidString                           // not arrived yet
        try h.context.save()
        ServiceLog.backfillCompletedVisits(in: h.context)
        let record = try #require(try records(h).first)
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .notTracked)

        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.id = invoiceID
        invoice.invoiceNumber = "INV-0080"
        h.context.insert(invoice)
        #expect(ServiceLog.linkEarlierVisits(in: h.context) == 1)
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .invoiced)
        #expect(ServiceLog.linkEarlierVisits(in: h.context) == 0)
    }

    // Copied in before the catalog had arrived: its services catch up too.
    @Test func aCopiedJobCatchesUpWithTheCatalog() throws {
        let h = try Harness(stopCount: 1)
        let mowingID = UUID()
        let done = visit(h, h.client, .completed, daysAgo: 4)
        done.expectedServiceIDs = [mowingID.uuidString]
        try h.context.save()
        ServiceLog.backfillCompletedVisits(in: h.context)
        let record = try #require(try records(h).first)
        #expect(record.lines.isEmpty)
        let mowing = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 45, operatorID: "op")
        mowing.id = mowingID
        h.context.insert(mowing)
        ServiceLog.linkEarlierVisits(in: h.context)
        #expect(record.lines.map(\.name) == ["Mowing"])
    }

    // MARK: - Billing status

    @Test func theBillingStatusOfEachKindOfJob() throws {
        let h = try Harness(stopCount: 1)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0070"
        h.context.insert(invoice)
        func record(_ source: ServiceRecordSource, billable: Bool = true, invoiced: Bool = false) -> ServiceRecord {
            let record = ServiceRecord(operatorID: "op", sourceKey: "k:\(UUID())", source: source)
            record.isBillable = billable
            if invoiced { record.invoiceID = invoice.id.uuidString }
            h.context.insert(record)
            return record
        }
        #expect(ServiceLog.billingStatus(of: record(.visit), in: h.context) == .notBilled)
        #expect(ServiceLog.billingStatus(of: record(.visit, billable: false), in: h.context) == .noCharge)
        #expect(ServiceLog.billingStatus(of: record(.route, invoiced: true), in: h.context) == .invoiced)
        #expect(ServiceLog.billingStatus(of: record(.beforeLog), in: h.context) == .notTracked)
        #expect(ServiceLog.billingStatus(of: record(.beforeLog, billable: false), in: h.context) == .notTracked)
        #expect(ServiceLog.billingStatus(of: record(.beforeLog, invoiced: true), in: h.context) == .invoiced)
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

    // A copy made before the log and one tracked on another device: the
    // tracked one's source wins, whichever is older.
    @Test func trackedWorkWinsOverACopyFromBeforeTheLog() throws {
        let h = try Harness(stopCount: 1)
        let newer = copy(h, secondsAfter: 5)
        newer.source = .visit
        let older = copy(h, secondsAfter: 0)
        older.source = .beforeLog
        [newer, older].forEach { h.context.insert($0) }
        ServiceLog.mergeDuplicates(in: h.context, now: h.clock.addingTimeInterval(aDayLater))
        #expect(older.source == .visit)
        #expect(ServiceLog.isUnbilled(older, in: h.context))
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
