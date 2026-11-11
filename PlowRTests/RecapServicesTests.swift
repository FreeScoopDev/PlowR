import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The route recap's Record Expected Services: for a stop completed this run
/// with nothing recorded (Siri, Control Center, Complete Without Services),
/// the expected services, named first, then recorded as the route screen's
/// one tap records them. Never on top of work already recorded or invoiced.
@MainActor
struct RecapServicesTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    /// Mow (flat, $40), Edge (per square foot) and Aerate (switched off); every
    /// client measured at 1,234 sq ft and expecting all three, Edge first.
    struct Catalog {
        var mow: ServiceItem
        var edge: ServiceItem
        var aerate: ServiceItem
        var expectedIDs: [String] { [mow.id.uuidString, edge.id.uuidString] }
    }

    @discardableResult
    private func catalog(_ h: Harness) throws -> Catalog {
        let mow = ServiceItem(name: "Mow", category: "lawn", unitType: "flat", pricePerUnit: 40, operatorID: "op",
                              sortOrder: 1)
        let edge = ServiceItem(name: "Edge", category: "lawn", unitType: "perSqFt", pricePerUnit: 0.0173,
                               operatorID: "op", sortOrder: 2)
        let aerate = ServiceItem(name: "Aerate", category: "lawn", unitType: "flat", pricePerUnit: 30,
                                 operatorID: "op", sortOrder: 3)
        aerate.isActive = false
        [mow, edge, aerate].forEach { h.context.insert($0) }
        for client in h.clients {
            for (label, area) in [("Front", 1_000.0), ("Back", 234.0)] {
                let zone = PropertyZone(label: label)
                zone.areaSquareFeet = area
                h.context.insert(zone)
                zone.client = client
            }
            client.expectedServiceIDs = [edge.id.uuidString, mow.id.uuidString, aerate.id.uuidString]
        }
        try h.context.save()
        return Catalog(mow: mow, edge: edge, aerate: aerate)
    }

    private func services(_ h: Harness) throws -> [ServiceItem] {
        try h.context.fetch(FetchDescriptor<ServiceItem>())
    }

    private func plan(_ h: Harness, _ store: ActiveRouteStore) throws -> [RecapServices.Planned] {
        RecapServiceRecorder.plan(stops: store.sortedStops, catalog: try services(h), operatorID: "op",
                                  run: store.runID, in: h.context)
    }

    @discardableResult
    private func record(_ h: Harness, _ store: ActiveRouteStore, _ planned: [RecapServices.Planned],
                        save: ((ModelContext) throws -> Void)? = nil) throws -> RecapServiceRecorder.Outcome {
        RecapServiceRecorder.record(planned, stops: store.sortedStops, catalog: try services(h), operatorID: "op",
                                    run: store.runID, in: h.context, save: save ?? { try $0.save() })
    }

    private func runRecord(_ h: Harness, _ store: ActiveRouteStore, _ stop: RouteStop) throws -> ServiceRecord? {
        ServiceLog.runRecord(run: try #require(store.runID), stop: stop.id, in: h.context)
    }

    /// A run started, with its first `count` stops completed the way Siri
    /// and Control Center complete them: no services.
    private func run(_ h: Harness, completing count: Int) throws -> ActiveRouteStore {
        let store = h.makeStore()
        store.start(h.route)
        for _ in 0..<count {
            let stop = try #require(store.currentStop)
            #expect(store.completeCurrentStop(expecting: stop.id) != .stopChanged)
            h.clock += 600
        }
        try h.context.save()
        return store
    }

    // MARK: - The planner, as plain values

    private let active = [StopRecording.Service(id: "mow", name: "Mow", unitType: "flat", pricePerUnit: 40),
                          StopRecording.Service(id: "edge", name: "Edge", unitType: "flat", pricePerUnit: 10)]

    private func facts() -> RecapServices.StopFacts {
        RecapServices.StopFacts(stopID: UUID(), clientName: "Ann", completedThisRun: true, hasClient: true,
                                expected: ["edge", "gone", "mow"], zones: [], nothingRecorded: true, notOnInvoice: true)
    }

    @Test func aStopThatQualifiesGetsItsExpectedServicesInCatalogOrder() throws {
        let planned = try #require(RecapServices.plan(facts(), active: active))
        #expect(planned.serviceIDs == ["mow", "edge"])
        #expect(planned.names == ["Mow", "Edge"])
        #expect(RecapServices.servicesText(planned) == "Mow and Edge")
    }

    @Test func eachConditionFlipsAStopOut() {
        var notCompleted = facts(); notCompleted.completedThisRun = false
        var noClient = facts(); noClient.hasClient = false
        var nothingExpected = facts(); nothingExpected.expected = ["gone"]
        var somethingRecorded = facts(); somethingRecorded.nothingRecorded = false
        var invoiced = facts(); invoiced.notOnInvoice = false
        for stop in [notCompleted, noClient, nothingExpected, somethingRecorded, invoiced] {
            #expect(RecapServices.plan(stop, active: active) == nil)
        }
        #expect(RecapServices.plan([facts(), invoiced, facts()], active: active).count == 2)
    }

    @Test func titlesSaySingularAndPlural() {
        #expect(RecapServices.buttonTitle(count: 1) == "Record Expected Services for 1 Stop")
        #expect(RecapServices.buttonTitle(count: 3) == "Record Expected Services for 3 Stops")
        #expect(RecapServices.confirmTitle(count: 1) == "Record for 1 Stop")
        #expect(RecapServices.confirmTitle(count: 2) == "Record for 2 Stops")
        #expect(RecapServices.notRecordedMessage([]) == nil)
        #expect(RecapServices.notRecordedMessage(["Ann"]) == "Not recorded for Ann: its record changed.")
        #expect(RecapServices.notRecordedMessage(["Ann", "Bo"]) == "Not recorded for Ann and Bo: their records changed.")
        #expect(RecapServices.afterConfirm(saveFailed: true, notRecorded: ["Ann"]) == RecapServices.saveFailedMessage)
    }

    // MARK: - Which stops, from the database

    @Test func aSiriStyleCompletionIsOfferedAndRecorded() throws {
        let h = try Harness()
        let c = try catalog(h)
        let store = try run(h, completing: 1)
        let stop = store.sortedStops[0]
        #expect(stop.completedServiceIDs.isEmpty)
        let planned = try plan(h, store)
        #expect(planned == [RecapServices.Planned(stopID: stop.id, clientName: "Client 0",
                                                  serviceIDs: c.expectedIDs, names: ["Mow", "Edge"])])
        let outcome = try record(h, store, planned)
        #expect(outcome.notRecorded.isEmpty)
        #expect(outcome.recorded.map(\.stopID) == [stop.id])
        #expect(stop.completedServiceIDs == c.expectedIDs)
        let saved = try #require(try runRecord(h, store, stop))
        #expect(saved.lines.map(\.name) == ["Mow", "Edge"])
        // Saved at once, not left to autosave.
        #expect(!h.context.hasChanges)
        // Offered no more.
        #expect(try plan(h, store).isEmpty)
        // Unbilled work, for Bill Unbilled Work.
        #expect(ServiceLog.isUnbilled(saved, in: h.context))
    }

    @Test func itRecordsTheSameLinesTheOneTapWould() throws {
        let h = try Harness()
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStop)
        store.completeCurrentStop(expecting: first.id)
        let second = try #require(store.currentStop)
        store.completeCurrentStop(expecting: second.id, recordingServices: c.expectedIDs)
        try h.context.save()
        let planned = try plan(h, store)
        #expect(planned.map(\.stopID) == [first.id])
        try record(h, store, planned)
        let recapped = try #require(try runRecord(h, store, first))
        let oneTap = try #require(try runRecord(h, store, second))
        #expect(!recapped.lines.isEmpty)
        #expect(recapped.lines == oneTap.lines)
        #expect(first.completedServiceIDs == second.completedServiceIDs)
    }

    @Test func theRecordsTimesAndEverythingElseStayAsTheyWere() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = try run(h, completing: 1)
        let stop = store.sortedStops[0]
        let saved = try #require(try runRecord(h, store, stop))
        saved.arrivedAt = h.clock.addingTimeInterval(-900)
        saved.leftAt = h.clock.addingTimeInterval(-100)
        saved.notes = "Gate code 12"
        try h.context.save()
        var before = ServiceRecord.Fields(of: saved)
        #expect(saved.startedAt != nil && saved.minutes >= 0)
        h.clock += 3_600
        try record(h, store, try plan(h, store))
        var after = ServiceRecord.Fields(of: saved)
        #expect(after.servicesData != before.servicesData)
        // Only the lines changed.
        before.servicesData = Data()
        after.servicesData = Data()
        #expect(after == before)
    }

    @Test func aStopNotCompletedThisRunIsNeverOffered() throws {
        let h = try Harness(stopCount: 3)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        // Passed below its trigger: no record.
        let passed = try #require(store.currentStop)
        #expect(store.passCurrentStop(expecting: passed.id) == .advanced(nextStopIndex: 1))
        // Notes saved in Record Services on a stop never completed: a record
        // without the completion's times.
        let unreached = store.sortedStops[2]
        let recording = StopRecording(services: ServiceLog.activeServices(try services(h), operatorID: "op"), zones: [])
        ServiceLog.saveRecording(recording, notes: "Dog in yard", for: unreached, of: h.clients[2],
                                 run: try #require(store.runID), operatorID: "op", startedAt: h.clock, in: h.context)
        try h.context.save()
        #expect(try runRecord(h, store, unreached) != nil)
        #expect(try plan(h, store).isEmpty)
        // Handed to the recorder anyway, nothing is written.
        let forced = [RecapServices.Planned(stopID: unreached.id, clientName: "Client 2", serviceIDs: c.expectedIDs,
                                            names: ["Mow", "Edge"])]
        #expect(try record(h, store, forced).notRecorded == ["Client 2"])
        #expect(unreached.completedServiceIDs.isEmpty)
        #expect(try runRecord(h, store, unreached)?.lines.isEmpty == true)
    }

    @Test func anotherRunsRecordIsNeverOffered() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = try run(h, completing: 1)
        #expect(try plan(h, store).count == 1)
        store.end()
        store.start(h.route)
        try h.context.save()
        #expect(try plan(h, store).isEmpty)
    }

    @Test func aCustomStopOrAGoneClientIsNeverOffered() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let custom = RouteStop(order: 2, customName: "Depot")
        custom.route = h.route
        h.context.insert(custom)
        StopServices.setForThisRoute(c.expectedIDs, on: custom)
        try h.context.save()
        let store = try run(h, completing: 3)
        #expect(try plan(h, store).count == 2)
        h.context.delete(h.clients[1])
        try h.context.save()
        #expect(try plan(h, store).map(\.clientName) == ["Client 0"])
    }

    @Test func aStopWithNothingExpectedInTheCatalogIsNeverOffered() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        h.clients[0].expectedServiceIDs = [c.aerate.id.uuidString]
        let store = try run(h, completing: 2)
        #expect(try plan(h, store).map(\.clientName) == ["Client 1"])
    }

    @Test func servicesOnTheStopKeepItOut() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = try run(h, completing: 2)
        store.sortedStops[0].completedServiceIDs = [c.mow.id.uuidString]
        #expect(try plan(h, store).map(\.clientName) == ["Client 1"])
    }

    @Test func aRecordWithACustomItemIsUntouched() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = try run(h, completing: 2)
        let stop = store.sortedStops[0]
        var recording = StopRecording(services: ServiceLog.activeServices(try services(h), operatorID: "op"), zones: [])
        recording.customItems = [StopRecording.CustomItem(name: "Haul brush", price: "25")]
        ServiceLog.saveRecording(recording, notes: "", for: stop, of: h.clients[0], run: try #require(store.runID),
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        try h.context.save()
        #expect(stop.completedServiceIDs.isEmpty)
        let saved = try #require(try runRecord(h, store, stop))
        let before = ServiceRecord.Fields(of: saved)
        #expect(try plan(h, store).map(\.clientName) == ["Client 1"])
        let forced = [RecapServices.Planned(stopID: stop.id, clientName: "Client 0", serviceIDs: c.expectedIDs,
                                            names: ["Mow", "Edge"])]
        #expect(try record(h, store, forced).notRecorded == ["Client 0"])
        #expect(ServiceRecord.Fields(of: saved) == before)
        #expect(stop.completedServiceIDs.isEmpty)
    }

    @Test func anInvoicedRecordIsUntouched() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        // An invoice made for the day's visit before the work: the record
        // completing makes is billed on it at once.
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0040"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        try h.context.save()
        let store = try run(h, completing: 2)
        let stop = store.sortedStops[0]
        let saved = try #require(try runRecord(h, store, stop))
        #expect(saved.invoiceID == invoice.id.uuidString)
        let before = ServiceRecord.Fields(of: saved)
        let proposals = try h.context.fetch(FetchDescriptor<Proposal>()).count
        #expect(try plan(h, store).map(\.clientName) == ["Client 1"])
        let forced = [RecapServices.Planned(stopID: stop.id, clientName: "Client 0", serviceIDs: c.expectedIDs,
                                            names: ["Mow", "Edge"])]
        #expect(try record(h, store, forced).notRecorded == ["Client 0"])
        #expect(ServiceRecord.Fields(of: saved) == before)
        #expect(try h.context.fetch(FetchDescriptor<Proposal>()).count == proposals)
    }

    @Test func aRecordWithAnInvoiceIDIsNeverOffered() throws {
        // The invoice is gone (deleted on another device): the one tap's
        // question would let it through, the record's invoiceID doesn't.
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = try run(h, completing: 2)
        let saved = try #require(try runRecord(h, store, store.sortedStops[0]))
        saved.invoiceID = UUID().uuidString
        try h.context.save()
        #expect(ServiceLog.hasNothingRecorded(for: store.sortedStops[0], of: h.clients[0],
                                              run: try #require(store.runID), startedAt: h.clock, in: h.context))
        #expect(try plan(h, store).map(\.clientName) == ["Client 1"])
    }

    // MARK: - Between the confirmation and Confirm

    @Test func aStopThatChangedSinceTheConfirmationIsLeftAndReported() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = try run(h, completing: 2)
        let planned = try plan(h, store)
        #expect(planned.count == 2)
        // Record Services saved Mow at a typed price on the first, meanwhile.
        let first = store.sortedStops[0]
        let recording = StopRecording(services: ServiceLog.activeServices(try services(h), operatorID: "op"),
                                      zones: [], selectedIDs: [c.mow.id.uuidString],
                                      typedPrices: [c.mow.id.uuidString: "55"])
        ServiceLog.saveRecording(recording, notes: "", for: first, of: h.clients[0], run: try #require(store.runID),
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        try h.context.save()
        let outcome = try record(h, store, planned)
        #expect(outcome.notRecorded == ["Client 0"])
        #expect(outcome.recorded.map(\.clientName) == ["Client 1"])
        #expect(RecapServices.afterConfirm(saveFailed: false, notRecorded: outcome.notRecorded)
                == "Not recorded for Client 0: its record changed.")
        #expect(first.completedServiceIDs == [c.mow.id.uuidString])
        let kept = try #require(try runRecord(h, store, first))
        #expect(kept.lines.map(\.price) == [55])
        #expect(store.sortedStops[1].completedServiceIDs == c.expectedIDs)
    }

    @Test func aServiceTheConfirmationDidntNameIsNeverRecorded() throws {
        let h = try Harness(stopCount: 1)
        let c = try catalog(h)
        let store = try run(h, completing: 1)
        let planned = try plan(h, store)
        // Aerate switched back on after the confirmation was drawn: what's
        // expected now isn't what it named.
        c.aerate.isActive = true
        try h.context.save()
        let outcome = try record(h, store, planned)
        #expect(outcome.recorded.isEmpty)
        #expect(outcome.notRecorded == ["Client 0"])
        #expect(store.sortedStops[0].completedServiceIDs.isEmpty)
    }

    @Test func aFailedSaveRecordsNothing() throws {
        let h = try Harness(stopCount: 1)
        try catalog(h)
        let store = try run(h, completing: 1)
        // Something else waiting to be saved, unrelated to the recap.
        h.clients[0].notes = "Waiting to be saved"
        let before = try #require(try runRecord(h, store, store.sortedStops[0])).servicesData
        struct Failed: Error {}
        var saves = 0
        let outcome = try record(h, store, try plan(h, store), save: { _ in saves += 1; throw Failed() })
        #expect(saves == 1)
        #expect(outcome.saveFailed)
        #expect(outcome.recorded.isEmpty)
        #expect(store.sortedStops[0].completedServiceIDs.isEmpty)
        #expect(try runRecord(h, store, store.sortedStops[0])?.lines.isEmpty == true)
        // Only the recap's own writes were taken back.
        #expect(h.clients[0].notes == "Waiting to be saved")
        // To the byte: Undo compares the record's fields.
        #expect(try runRecord(h, store, store.sortedStops[0])?.servicesData == before)
    }

    // MARK: - Per square foot with no measured area

    @Test func thePlannerLeavesOutPerSquareFootWithNoArea() throws {
        let edge = StopRecording.Service(id: "edge", name: "Edge", unitType: "perSqFt", pricePerUnit: 0.02)
        let catalog = [active[0], edge]
        var stop = facts()
        // No area: Mow only, never Edge at $0.
        #expect(RecapServices.plan(stop, active: catalog)?.serviceIDs == ["mow"])
        // Measured: both.
        stop.zones = [InvoiceLines.Zone(label: "Front", areaSquareFeet: 500)]
        #expect(RecapServices.plan(stop, active: catalog)?.serviceIDs == ["mow", "edge"])
        // Only Edge expected, no area: the stop isn't offered.
        var onlyEdge = facts()
        onlyEdge.expected = ["edge"]
        #expect(RecapServices.plan(onlyEdge, active: catalog) == nil)
    }

    @Test func aStopExpectingOnlyUnpricedServicesIsNeverOffered() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        for client in h.clients {
            for zone in client.zones ?? [] { h.context.delete(zone) }
            client.zones = []
        }
        h.clients[0].expectedServiceIDs = [c.edge.id.uuidString]
        try h.context.save()
        let store = try run(h, completing: 2)
        let planned = try plan(h, store)
        // The second stop is offered Mow alone; the first, nothing.
        #expect(planned == [RecapServices.Planned(stopID: store.sortedStops[1].id, clientName: "Client 1",
                                                  serviceIDs: [c.mow.id.uuidString], names: ["Mow"])])
        try record(h, store, planned)
        let saved = try #require(try runRecord(h, store, store.sortedStops[1]))
        #expect(saved.lines.map(\.name) == ["Mow"])
        #expect(saved.lines.allSatisfy { $0.price > 0 })
    }

    // MARK: - Worked out once per change; Confirm once

    private func records(_ h: Harness, _ store: ActiveRouteStore) throws -> [ServiceRecord] {
        let id = try #require(store.runID).uuidString
        return try h.context.fetch(FetchDescriptor<ServiceRecord>(predicate: #Predicate { $0.runID == id }))
    }

    /// The recap redraws often: the plan is read again only when the run's
    /// records, the stops' services, the catalog or the database changed.
    @Test func thePlanIsWorkedOutAgainOnlyWhenSomethingChanged() throws {
        let h = try Harness()
        let c = try catalog(h)
        let store = try run(h, completing: 1)
        let memo = RecapPlanMemo()
        func draw(_ version: Int) throws -> [RecapServices.Planned] {
            RecapServiceRecorder.plan(stops: store.sortedStops, catalog: try services(h), operatorID: "op",
                                      run: store.runID, records: try records(h, store), in: h.context,
                                      memo: memo, dataVersion: version)
        }
        let first = try draw(0)
        #expect(first.count == 1)
        #expect(try draw(0) == first)
        #expect(memo.computed == 1)
        // A save or synced change: worked out again.
        #expect(try draw(1) == first)
        #expect(memo.computed == 2)
        // Services recorded on a stop (not yet saved): worked out again, and
        // it's offered no more.
        store.sortedStops[0].completedServiceIDs = [c.mow.id.uuidString]
        #expect(try draw(1).isEmpty)
        #expect(memo.computed == 3)
        // A catalog change: worked out again.
        store.sortedStops[0].completedServiceIDs = []
        _ = try draw(1)
        let computed = memo.computed
        c.mow.name = "Mowing"
        #expect(try draw(1).first?.names == ["Mowing", "Edge"])
        #expect(memo.computed == computed + 1)
    }

    /// Confirm runs once: a second tap before the sheet closes would find
    /// every stop recorded and say none were.
    @Test func confirmRunsOnce() {
        var confirm = RecapServices.ConfirmOnce()
        var runs = 0
        confirm.run { runs += 1 }
        confirm.run { runs += 1 }
        #expect(runs == 1)
        #expect(confirm.done)
    }

    /// Why it matters: run twice, the second finds nothing to record and
    /// would report every stop as not recorded.
    @Test func aSecondConfirmWouldReportEveryStopAsNotRecorded() throws {
        let h = try Harness()
        try catalog(h)
        let store = try run(h, completing: 1)
        let planned = try plan(h, store)
        #expect(try record(h, store, planned).notRecorded.isEmpty)
        #expect(try record(h, store, planned).notRecorded == ["Client 0"])
    }
}
