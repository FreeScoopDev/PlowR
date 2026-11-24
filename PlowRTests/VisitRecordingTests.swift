//
//  VisitRecordingTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Record Services for a visit (the visit sheet): `ServiceLog.saveVisitRecording`
/// writes the visit's one `visit:<id>` record through the same paths as
/// Complete and a route stop, and Record Services' invoice links the visit.
@MainActor
struct VisitRecordingTests {
    typealias Visits = ServiceLogTests.Visits

    private func records(_ v: Visits) throws -> [ServiceRecord] {
        try v.context.fetch(FetchDescriptor<ServiceRecord>())
    }

    /// A catalog service, and the sheet's view of the catalog.
    private func service(_ v: Visits, _ name: String, _ price: Double, order: Int = 0) -> ServiceItem {
        let item = ServiceItem(name: name, category: "lawn", unitType: "flat", pricePerUnit: price, operatorID: "op",
                               sortOrder: order)
        v.context.insert(item)
        return item
    }

    private func catalog(_ v: Visits) throws -> [StopRecording.Service] {
        ServiceLog.activeServices(try v.context.fetch(FetchDescriptor<ServiceItem>()), operatorID: "op")
    }

    /// The sheet as it opens for `visit` with nothing saved: its expected
    /// services ticked at its prices. The same function the sheet calls
    /// (StopServiceRecorderView.loadVisitRecord).
    private func openedSheet(_ v: Visits, for visit: ScheduledVisit) throws -> StopRecording {
        StopRecording.opening(visit: visit, client: v.client, services: try catalog(v),
                              zones: Place.zones(of: v.client, propertyID: visit.propertyID), in: v.context)
    }

    /// The Save menu's invoice items for `visit`, as the recorder works them out.
    private func recorderOffersInvoice(_ visit: ScheduledVisit, _ v: Visits) -> Bool {
        StopServiceRecorderView.offersInvoiceItems(
            invoicedAs: nil, canEdit: true,
            visitWorkBillable: ServiceLog.isVisitWorkBillable(visit, client: v.client, in: v.context))
    }

    private func save(_ recording: StopRecording, notes: String = "", _ visit: ScheduledVisit,
                      _ v: Visits) -> ServiceRecord {
        ServiceLog.saveVisitRecording(recording, notes: notes, for: visit, client: v.client, operatorID: "op",
                                      now: v.now, in: v.context)
    }

    // MARK: - Completing through Record Services

    @Test func savingAScheduledVisitCompletesItAndWritesTheLines() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45, order: 1)
        let edge = service(v, "Edging", 20, order: 2)
        let visit = v.visit(hoursFromNow: -2)
        visit.expectedServiceIDs = [mow.id.uuidString]

        var sheet = try openedSheet(v, for: visit)
        #expect(sheet.selectedIDs == [mow.id.uuidString])     // expected start ticked
        sheet.selectedIDs.insert(edge.id.uuidString)
        let record = save(sheet, notes: "Gate open", visit, v)

        #expect(visit.status == .completed)
        #expect(visit.completedAt == v.now)
        #expect(visit.serviceLogged)
        #expect(record.sourceKey == ServiceLog.visitKey(visit.id))
        #expect(record.source == .visit)
        #expect(record.visitID == visit.id.uuidString)
        #expect(record.performedAt == visit.scheduledDate)
        #expect(record.lines.map(\.name) == ["Mowing", "Edging"])
        #expect(record.lines.map(\.price) == [45, 20])
        #expect(record.notes == "Gate open")
        #expect(try records(v).count == 1)
    }

    @Test func aRepeatingVisitGetsItsNextVisitOnceHoweverOftenItsSaved() throws {
        let v = try Visits()
        let visit = v.visit(hoursFromNow: -1)
        visit.isRecurring = true
        visit.recurrenceType = .weekly
        visit.seriesID = UUID().uuidString
        let sheet = StopRecording(services: try catalog(v), zones: [], customItems: [.init(name: "Cleanup", price: "30")])
        save(sheet, visit, v)
        save(sheet, visit, v)
        let next = try v.all().filter { $0.id != visit.id }
        #expect(next.count == 1)
        #expect(next.first?.status == .scheduled)
        #expect(try records(v).count == 1)
    }

    // The after-hours price is the same whether the visit is ticked off with
    // Complete or saved from Record Services as it opened.
    @Test func anAfterHoursVisitIsPricedAsCompletePricesIt() throws {
        let v = try Visits()
        let clear = service(v, "Clear", 40, order: 1)
        let salt = service(v, "Salt", 25, order: 2)
        func afterHours() -> ScheduledVisit {
            let visit = v.visit(hoursFromNow: -1)
            visit.expectedServiceIDs = [salt.id.uuidString, clear.id.uuidString]
            visit.isAfterHours = true
            visit.afterHoursMultiplier = 1.5
            return visit
        }
        let completed = try #require(ServiceLog.complete(afterHours(), among: try v.all(), in: v.context, now: v.now))
        let recordedVisit = afterHours()
        let recorded = save(try openedSheet(v, for: recordedVisit), recordedVisit, v)
        #expect(recorded.lines == completed.lines)
        #expect(recorded.lines.map(\.price) == [60, 37.5])
    }

    // MARK: - A record that exists

    // A route stop that shared the visit made its record: editing it from
    // the visit keeps its times, route and source.
    @Test func editingARouteStopsRecordKeepsItsTimes() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45)
        let visit = v.visit(hoursFromNow: -3)
        visit.status = .completed
        visit.completedAt = v.now.addingTimeInterval(-3_600)
        let record = ServiceRecord(operatorID: "op", sourceKey: ServiceLog.visitKey(visit.id), source: .route)
        record.clientID = v.client.id.uuidString
        record.visitID = visit.id.uuidString
        let started = v.now.addingTimeInterval(-2 * 3_600)
        record.startedAt = started
        record.arrivedAt = started.addingTimeInterval(300)
        record.leftAt = started.addingTimeInterval(1_500)
        record.performedAt = started.addingTimeInterval(1_800)
        record.minutes = 30
        record.routeID = "route"
        record.routeName = "Tuesday"
        record.runID = "run"
        record.stopID = "stop"
        record.isBillable = false
        v.context.insert(record)

        var sheet = StopRecording(services: try catalog(v), zones: [])
        sheet.selectedIDs = [mow.id.uuidString]
        let saved = save(sheet, notes: "Edged too", visit, v)

        #expect(saved.id == record.id)
        #expect(saved.lines.map(\.name) == ["Mowing"])
        #expect(saved.notes == "Edged too")
        #expect(saved.source == .route)
        #expect(saved.startedAt == started)
        #expect(saved.arrivedAt == started.addingTimeInterval(300))
        #expect(saved.leftAt == started.addingTimeInterval(1_500))
        #expect(saved.performedAt == started.addingTimeInterval(1_800))
        #expect(saved.minutes == 30)
        #expect(saved.routeID == "route")
        #expect(saved.routeName == "Tuesday")
        #expect(saved.runID == "run")
        #expect(saved.stopID == "stop")
        #expect(!saved.isBillable)
        #expect(visit.completedAt == v.now.addingTimeInterval(-3_600))
        #expect(try records(v).count == 1)
    }

    // On an invoice with services: they're fixed; notes still save.
    @Test func aLockedRecordKeepsItsServices() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45)
        let edge = service(v, "Edging", 20)
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [mow.id.uuidString]
        let record = try #require(ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now))
        let invoice = ServiceLog.newDraftInvoice(for: v.client, items: [], operatorID: "op", now: v.now, in: v.context)
        record.invoiceID = invoice.id.uuidString
        #expect(ServiceLog.servicesLocked(record, in: v.context))

        var sheet = StopRecording(services: try catalog(v), zones: [])
        sheet.selectedIDs = [edge.id.uuidString]
        save(sheet, notes: "Dog in yard", visit, v)
        #expect(record.lines.map(\.name) == ["Mowing"])
        #expect(record.notes == "Dog in yard")
        #expect(record.invoiceID == invoice.id.uuidString)
    }

    // A completed visit whose record was deleted gets one again, as Complete makes it.
    @Test func aCompletedVisitWithoutARecordGetsOne() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45)
        let visit = v.visit(hoursFromNow: -30)
        visit.status = .completed
        visit.completedAt = v.now.addingTimeInterval(-3_600)
        var sheet = StopRecording(services: try catalog(v), zones: [])
        sheet.selectedIDs = [mow.id.uuidString]
        let record = save(sheet, visit, v)
        #expect(record.source == .visit)
        #expect(record.visitID == visit.id.uuidString)
        #expect(record.performedAt == visit.scheduledDate)
        #expect(record.lines.map(\.name) == ["Mowing"])
        #expect(try v.all().count == 1)    // not completed again: no series work
    }

    // MARK: - Invoices

    // Invoiced beforehand (Schedule → Invoice): the record Record Services
    // makes is billed on that invoice, with the services recorded, even
    // where Complete had filled in the expected ones.
    @Test func aVisitInvoicedBeforehandRecordsOntoThatInvoice() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45)
        let edge = service(v, "Edging", 20)
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [mow.id.uuidString]
        let invoice = ServiceLog.newDraftInvoice(for: v.client, items: [], operatorID: "op", now: v.now, in: v.context)
        visit.proposalID = invoice.id.uuidString

        var sheet = StopRecording(services: try catalog(v), zones: [])
        sheet.selectedIDs = [edge.id.uuidString]
        let record = save(sheet, visit, v)
        #expect(record.invoiceID == invoice.id.uuidString)
        #expect(record.lines.map(\.name) == ["Edging"])
        #expect(ServiceLog.isVisitBilled(visit, in: v.context))
    }

    // Complete & Invoice: Record Services' invoice links the visit, so it's
    // billed and the Schedule won't offer to invoice it again.
    @Test func completeAndInvoiceLinksTheVisit() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45)
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [mow.id.uuidString]
        let sheet = try openedSheet(v, for: visit)
        let record = save(sheet, visit, v)
        let proposal = try #require(ServiceLog.invoice(record, recording: sheet, under: nil, client: v.client,
                                                       operatorID: "op", notes: "", now: v.now, in: v.context))
        #expect(visit.proposalID == proposal.id.uuidString)
        #expect(proposal.visitID == visit.id.uuidString)
        #expect(record.invoiceID == proposal.id.uuidString)
        #expect(ServiceLog.isVisitBilled(visit, in: v.context))
        #expect(visit.status == .completed)
        let plan = VisitActions(VisitActions.facts(for: visit, client: v.client, canEdit: true, in: v.context))
        #expect(plan.actions.contains(.viewInvoice))
        #expect(!plan.actions.contains(.invoiceWork))
    }

    // A season contract covering the work: saved and completed, no invoice.
    @Test func workAContractCoversIsSavedWithNoInvoice() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45)
        var draft = Contracts.Draft(for: v.client, now: v.now.addingTimeInterval(-10 * 86_400))
        draft.pricing = .season
        draft.priceText = "900"
        draft.serviceIDs = [mow.id.uuidString]
        let contract = Contracts.save(draft, to: nil, of: v.client, in: v.context)
        Contracts.sign(contract, in: v.context, now: v.now.addingTimeInterval(-10 * 86_400))
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [mow.id.uuidString]

        let sheet = try openedSheet(v, for: visit)
        let record = save(sheet, visit, v)
        let covering = Contracts.contract(coveringPlace: Place.id(of: v.client, propertyID: visit.propertyID),
                                          of: v.client.id.uuidString, on: visit.scheduledDate,
                                          among: Contracts.all(in: v.context))
        #expect(covering?.id == contract.id)
        #expect(ServiceLog.invoice(record, recording: sheet, under: covering, client: v.client, operatorID: "op",
                                   notes: "", now: v.now, in: v.context) == nil)
        #expect(visit.status == .completed)
        #expect(record.lines.map(\.name) == ["Mowing"])
        #expect(!ServiceLog.isVisitBilled(visit, in: v.context))
    }

    // MARK: - No client, comped client

    @Test func aVisitForADeletedClientRecordsAndBillsNothing() throws {
        let v = try Visits()
        let visit = ScheduledVisit(operatorID: "op", clientID: UUID().uuidString, clientName: "Gone",
                                   clientAddress: "", scheduledDate: v.now)
        v.context.insert(visit)
        let plan = VisitActions(VisitActions.facts(for: visit, client: nil, canEdit: true, in: v.context))
        #expect(plan.actions == [.complete, .editVisit])
        #expect(ServiceLog.complete(visit, among: try v.all(), in: v.context, now: v.now) == nil)
        #expect(visit.status == .completed)
        #expect(try records(v).isEmpty)
        #expect(try v.context.fetch(FetchDescriptor<Proposal>()).isEmpty)
    }

    @Test func aCompedClientsWorkIsNotBillable() throws {
        let v = try Visits()
        v.client.isComped = true
        let mow = service(v, "Mowing", 45)
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [mow.id.uuidString]
        let record = save(try openedSheet(v, for: visit), visit, v)
        #expect(!record.isBillable)
        #expect(ServiceLog.billingStatus(of: record, in: v.context) == .noCharge)
        // The visit's Save menu offers no invoice for them; a stop's is unchanged.
        #expect(!recorderOffersInvoice(visit, v))
        #expect(StopServiceRecorderView.offersInvoiceItems(invoicedAs: nil, canEdit: true, visitWorkBillable: nil))
    }

    // Work done while the client was comped stays unbilled after they
    // aren't: the record decides, in the sheet and the recorder alike.
    @Test func workDoneWhileCompedIsNotInvoicedAfterTheClientIsUncomped() throws {
        let v = try Visits()
        v.client.isComped = true
        let mow = service(v, "Mowing", 45)
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [mow.id.uuidString]
        save(try openedSheet(v, for: visit), visit, v)
        v.client.isComped = false

        #expect(!ServiceLog.isVisitWorkBillable(visit, client: v.client, in: v.context))
        #expect(!recorderOffersInvoice(visit, v))
        let plan = VisitActions(VisitActions.facts(for: visit, client: v.client, canEdit: true, in: v.context))
        #expect(!plan.actions.contains(.invoiceWork))
        #expect(plan.reasons == ["This work is marked no charge."])
    }

    // Billable work whose client is comped since: still billable, and the
    // sheet's Invoice Work and the recorder's invoice items agree.
    @Test func billableWorkStaysBillableAfterTheClientIsComped() throws {
        let v = try Visits()
        let mow = service(v, "Mowing", 45)
        let visit = v.visit(hoursFromNow: -1)
        visit.expectedServiceIDs = [mow.id.uuidString]
        let record = save(try openedSheet(v, for: visit), visit, v)
        #expect(record.isBillable)
        v.client.isComped = true

        let plan = VisitActions(VisitActions.facts(for: visit, client: v.client, canEdit: true, in: v.context))
        #expect(plan.actions.contains(.invoiceWork))
        #expect(recorderOffersInvoice(visit, v))
    }

    // Before any record, the client decides, in both places.
    @Test func withNoRecordTheClientDecidesInBothPlaces() throws {
        let v = try Visits()
        let visit = v.visit(hoursFromNow: -1)
        for comped in [false, true] {
            v.client.isComped = comped
            let plan = VisitActions(VisitActions.facts(for: visit, client: v.client, canEdit: true, in: v.context))
            #expect(plan.actions.contains(.completeAndInvoice) == !comped)
            #expect(recorderOffersInvoice(visit, v) == !comped)
        }
        #expect(!ServiceLog.isVisitWorkBillable(visit, client: nil, in: v.context))
    }

    @Test func nothingToBillSaysWhy() {
        #expect(StopServiceRecorderView.nothingToBillMessage(contractName: "Season", hasServices: true)
                == "Nothing to bill: Season covers this work.")
        #expect(StopServiceRecorderView.nothingToBillMessage(contractName: nil, hasServices: true)
                == "Nothing to bill: the services recorded have no price.")
        #expect(StopServiceRecorderView.nothingToBillMessage(contractName: nil, hasServices: false)
                == "Nothing to bill: no services were recorded.")
    }

    // MARK: - A route stop's Record Services is unchanged

    @Test func theSaveMenuRuleForAStopIsUnchanged() {
        #expect(StopServiceRecorderView.offersInvoiceItems(invoicedAs: nil, canEdit: true, visitWorkBillable: nil))
        #expect(!StopServiceRecorderView.offersInvoiceItems(invoicedAs: "INV-1", canEdit: true, visitWorkBillable: nil))
        #expect(!StopServiceRecorderView.offersInvoiceItems(invoicedAs: nil, canEdit: false, visitWorkBillable: nil))
    }

    // saveRecording through the shared tail: notes on the stop and record,
    // services and the stop's IDs while unlocked; once on an invoice, only notes.
    @Test func aStopsSaveRecordingStillWritesAsBefore() throws {
        let h = try ActiveRouteStoreTests.Harness(stopCount: 1)
        let mow = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 45, operatorID: "op")
        let edge = ServiceItem(name: "Edging", category: "lawn", unitType: "flat", pricePerUnit: 20, operatorID: "op")
        [mow, edge].forEach { h.context.insert($0) }
        let stop = try #require(h.route.sortedStops.first)
        let run = UUID()
        let services = ServiceLog.activeServices([mow, edge], operatorID: "op")
        var sheet = StopRecording(services: services, zones: [])
        sheet.selectedIDs = [mow.id.uuidString]
        let record = ServiceLog.saveRecording(sheet, notes: "First", for: stop, of: h.client, run: run,
                                              operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(record.lines.map(\.name) == ["Mowing"])
        #expect(record.notes == "First")
        #expect(stop.completedNotes == "First")
        #expect(stop.completedServiceIDs == [mow.id.uuidString])
        #expect(record.startedAt == nil)
        #expect(record.minutes == 0)

        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [], operatorID: "op", now: h.clock, in: h.context)
        record.invoiceID = invoice.id.uuidString
        sheet.selectedIDs = [edge.id.uuidString]
        ServiceLog.saveRecording(sheet, notes: "Second", for: stop, of: h.client, run: run, operatorID: "op",
                                 startedAt: h.clock, in: h.context)
        #expect(record.lines.map(\.name) == ["Mowing"])
        #expect(record.notes == "Second")
        #expect(stop.completedNotes == "Second")
        #expect(stop.completedServiceIDs == [mow.id.uuidString])

        // An invoice since deleted: unbilled again, and the services change.
        h.context.delete(invoice)
        try h.context.save()
        ServiceLog.saveRecording(sheet, notes: "Third", for: stop, of: h.client, run: run, operatorID: "op",
                                 startedAt: h.clock, in: h.context)
        #expect(record.invoiceID.isEmpty)
        #expect(record.lines.map(\.name) == ["Edging"])
        #expect(stop.completedServiceIDs == [edge.id.uuidString])
    }
}
