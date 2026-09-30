//
//  StopRecordingTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Record Services saves to the Service Log, with or without an invoice. It
/// used to save only by making an invoice, and the log re-priced the stop's
/// services from the catalog, so a typed price or a custom item made the log
/// and the bill disagree.
@MainActor
struct StopRecordingTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private let zones = [InvoiceLines.Zone(label: "Front", areaSquareFeet: 600),
                         InvoiceLines.Zone(label: "Back", areaSquareFeet: 400)]

    private func recording(selected: Set<String> = ["salt", "clear"], typed: [String: String] = [:],
                           custom: [StopRecording.CustomItem] = []) -> StopRecording {
        StopRecording(
            services: [.init(id: "clear", name: "Clear", unitType: "flat", pricePerUnit: 40),
                       .init(id: "salt", name: "Salt", unitType: "perSqFt", pricePerUnit: 0.05),
                       .init(id: "edge", name: "Edging", unitType: "flat", pricePerUnit: 15)],
            zones: zones, selectedIDs: selected, typedPrices: typed, customItems: custom)
    }

    private func total(_ lines: [InvoiceLines.Line]) -> Int { lines.reduce(0) { $0 + InvoiceLines.cents($1.lineTotal) } }
    private func total(_ lines: [ServiceRecord.Line]) -> Int { lines.reduce(0) { $0 + InvoiceLines.cents($1.price) } }

    // MARK: - Pricing

    @Test func theLogAndTheInvoiceAddUpToTheSame() {
        let r = recording(typed: ["salt": "57.77"], custom: [.init(name: "Gate fix", price: "12.50")])
        #expect(total(r.invoiceLines) == total(r.recordLines))
        #expect(total(r.recordLines) == 4_000 + 5_777 + 1_250)
    }

    @Test func theLogHasOneLinePerServiceAtThePriceOnScreen() {
        let r = recording(typed: ["salt": "57.77"], custom: [.init(name: "Gate fix", price: "12.50")])
        #expect(r.recordLines.map(\.name) == ["Clear", "Salt", "Gate fix"])
        #expect(r.recordLines.map(\.price) == [40, 57.77, 12.5])
        #expect(r.recordLines.map(\.serviceID) == ["clear", "salt", ""])
        // The invoice splits the per-square-foot service across the zones.
        #expect(r.invoiceLines.map(\.zoneLabel) == ["All Zones", "Front", "Back", ""])
    }

    @Test func untouchedPricesAreTheCatalogsForTheProperty() {
        let r = recording()
        #expect(r.recordLines.map(\.price) == [40, 50])
    }

    @Test func customItemsWithoutANameOrPriceAreLeftOut() {
        let r = recording(selected: [], custom: [.init(name: "", price: "10"), .init(name: "Haul", price: ""),
                                                 .init(name: "Free", price: "0"), .init(name: " Haul ", price: "20")])
        #expect(r.recordLines.map(\.name) == ["Haul"])
        #expect(r.invoiceLines.map(\.lineTotal) == [20])
    }

    // MARK: - Saving

    private func services(_ h: Harness) -> (clear: ServiceItem, salt: ServiceItem) {
        let clear = ServiceItem(name: "Clear", category: "snow", unitType: "flat", pricePerUnit: 40, operatorID: "op",
                                sortOrder: 0)
        let salt = ServiceItem(name: "Salt", category: "snow", unitType: "flat", pricePerUnit: 10, operatorID: "op",
                               sortOrder: 1)
        h.context.insert(clear)
        h.context.insert(salt)
        return (clear, salt)
    }

    private func records(_ h: Harness) throws -> [ServiceRecord] { try h.context.fetch(FetchDescriptor<ServiceRecord>()) }

    private func screen(_ h: Harness, selected: [ServiceItem], typed: [String: String] = [:]) -> StopRecording {
        StopRecording(services: selected.map { .init(id: $0.id.uuidString, name: $0.name, unitType: $0.unitType,
                                                     pricePerUnit: $0.pricePerUnit) },
                      zones: [], selectedIDs: Set(selected.map(\.id.uuidString)), typedPrices: typed)
    }

    // Recorded, then the stop completed: one record, with the typed price
    // and the stop's times. Completing used to re-price from the catalog.
    @Test func recordingThenCompletingIsOneRecordAtTheTypedPrice() throws {
        let h = try Harness(stopCount: 2)
        let (clear, _) = services(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let run = try #require(store.runID)
        ServiceLog.saveRecording(screen(h, selected: [clear], typed: [clear.id.uuidString: "55"]), notes: "Icy",
                                 for: stop, of: h.client, run: run, operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(stop.completedServiceIDs == [clear.id.uuidString])
        h.clock = h.clock.addingTimeInterval(9 * 60)
        store.completeShownStop()

        let all = try records(h)
        #expect(all.count == 1)
        #expect(all.first?.lines.map(\.price) == [55])
        #expect(all.first?.notes == "Icy")
        #expect(all.first?.minutes == 9)
        #expect(all.first?.startedAt != nil)
    }

    // Saving again (reopened the sheet) replaces the services.
    @Test func savingAgainReplacesTheServices() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let run = UUID()
        ServiceLog.saveRecording(screen(h, selected: [clear]), notes: "", for: stop, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        ServiceLog.saveRecording(screen(h, selected: [salt]), notes: "", for: stop, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(try records(h).map { $0.lines.map(\.name) } == [["Salt"]])
    }

    // On an invoice, the record keeps matching the bill; notes still change.
    @Test func anInvoicedRecordKeepsItsServices() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let run = UUID()
        let first = screen(h, selected: [clear])
        let record = ServiceLog.saveRecording(first, notes: "", for: stop, of: h.client, run: run,
                                              operatorID: "op", startedAt: h.clock, in: h.context)
        let invoice = ServiceLog.invoice(record, lines: first.invoiceLines, client: h.client, operatorID: "op",
                                         notes: "", now: h.clock, in: h.context)
        ServiceLog.saveRecording(screen(h, selected: [salt]), notes: "Later note", for: stop, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(record.invoiceID == invoice.id.uuidString)
        #expect(record.lines.map(\.name) == ["Clear"])
        #expect(record.notes == "Later note")
        // The route screen's "N recorded" stays with the record, too.
        #expect(stop.completedServiceIDs == [clear.id.uuidString])
    }

    @Test func invoicingBillsTheRecordAndDeletingTheInvoiceUnbillsIt() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let screen = screen(h, selected: [clear], typed: [clear.id.uuidString: "45"])
        let record = ServiceLog.saveRecording(screen, notes: "n", for: stop, of: h.client, run: UUID(),
                                              operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(ServiceLog.isUnbilled(record, in: h.context))
        let invoice = ServiceLog.invoice(record, lines: screen.invoiceLines, client: h.client, operatorID: "op",
                                         notes: "n", now: h.clock, in: h.context)
        #expect(!ServiceLog.isUnbilled(record, in: h.context))
        #expect(invoice.isInvoice)
        #expect(invoice.total == 45)
        #expect(invoice.notes == "n")
        #expect(invoice.invoiceDueDate == h.clock.addingTimeInterval(30 * 86_400))

        ServiceLog.delete(invoice, in: h.context)
        try h.context.save()
        #expect(ServiceLog.isUnbilled(record, in: h.context))
        #expect(try h.context.fetch(FetchDescriptor<Proposal>()).isEmpty)
    }

    // An invoice made for a scheduled visit (Schedule → Invoice) bills the
    // visit's record.
    @Test func aVisitsInvoiceBillsItsRecord() throws {
        let h = try Harness(stopCount: 1)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0009"
        h.context.insert(invoice)
        ServiceLog.markVisitInvoiced(visitID: visit.id.uuidString, invoice: invoice, in: h.context)
        #expect(record.invoiceID == invoice.id.uuidString)
    }

    // Looking a record up for the sheet never makes one.
    @Test func lookingUpARecordDoesNotMakeOne() throws {
        let h = try Harness(stopCount: 1)
        let stop = try #require(h.route.sortedStops.first)
        #expect(ServiceLog.existingRecordForStop(stop, of: h.client, run: UUID(), startedAt: h.clock, in: h.context) == nil)
        #expect(try records(h).isEmpty)
    }

    // The sheet and the stop agree on the record when the stop is the day's
    // visit: saved before completing, completed after, still one record.
    @Test func recordingTheDaysVisitThenCompletingIsOneRecord() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        ServiceLog.saveRecording(screen(h, selected: [clear]), notes: "", for: stop, of: h.client,
                                 run: try #require(store.runID), operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(visit.status == .scheduled)          // recording alone doesn't complete it
        store.completeShownStop()
        #expect(visit.status == .completed)
        #expect(try records(h).count == 1)
    }
    // MARK: - Found the same way from the sheet and the stop

    private func visit(_ h: Harness, at date: Date) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: date)
        h.context.insert(visit)
        return visit
    }

    // A night route: services recorded at 23:50, the stop completed at 00:10.
    // The sheet and the stop used to each date the lookup by their own time,
    // so the day's visit was found by one and not the other: two records.
    @Test func aStopRecordedBeforeMidnightAndCompletedAfterIsOneRecord() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let day = Calendar.current.startOfDay(for: h.clock)
        let visit = visit(h, at: day.addingTimeInterval(12 * 3_600))
        try h.context.save()
        h.clock = day.addingTimeInterval(23 * 3_600 + 50 * 60)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let run = try #require(store.runID)
        let started = try #require(store.stopStartedAt)
        ServiceLog.saveRecording(screen(h, selected: [clear], typed: [clear.id.uuidString: "70"]), notes: "",
                                 for: stop, of: h.client, run: run, operatorID: "op", startedAt: started, in: h.context)
        h.clock = h.clock.addingTimeInterval(20 * 60)
        store.completeShownStop()

        let all = try records(h)
        #expect(all.count == 1)
        #expect(all.first?.lines.map(\.price) == [70])
        #expect(visit.status == .completed)
        // Reopened from the recap after midnight: the same record, not none.
        #expect(ServiceLog.existingRecordForStop(stop, of: h.client, run: run, startedAt: h.clock,
                                                 in: h.context)?.id == all.first?.id)
    }

    // Reopened from the recap, a completed stop's record is found by run and
    // stop, whatever day it is now. (It's under the day's visit's key, which
    // a lookup by today's date would miss.)
    @Test func aCompletedStopsRecordIsFoundByRunAndStop() throws {
        let h = try Harness(stopCount: 2)
        _ = visit(h, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        store.completeShownStop()
        let record = try #require(try records(h).first)
        let found = ServiceLog.existingRecordForStop(stop, of: h.client, run: try #require(store.runID),
                                                     startedAt: h.clock.addingTimeInterval(3 * 86_400), in: h.context)
        #expect(found?.id == record.id)
    }

    // A visit completed in the Schedule, then run on a route: the sheet finds
    // the Schedule's record (with its services) to load, so a save keeps them.
    @Test func theSheetFindsTheRecordTheScheduleMade() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let visit = visit(h, at: h.clock)
        visit.expectedServiceIDs = [clear.id.uuidString]
        let made = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let found = ServiceLog.existingRecordForStop(stop, of: h.client, run: try #require(store.runID),
                                                     startedAt: h.clock, in: h.context)
        #expect(found?.id == made.id)
        #expect(found?.lines.map(\.name) == ["Clear"])
    }

    // Schedule → Invoice before the work is done: the record made when it's
    // done is billed on that invoice, from the Schedule or from a route.
    @Test func aVisitInvoicedBeforeItsDoneIsBilledWhenItsDone() throws {
        let h = try Harness(stopCount: 1)
        let fromSchedule = visit(h, at: h.clock)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0010"
        h.context.insert(invoice)
        fromSchedule.proposalID = invoice.id.uuidString
        let record = try #require(ServiceLog.complete(fromSchedule, among: [fromSchedule], in: h.context, now: h.clock))
        #expect(record.invoiceID == invoice.id.uuidString)
    }

    @Test func aVisitInvoicedBeforeItsRunOnARouteIsBilled() throws {
        let h = try Harness(stopCount: 1)
        let visit = visit(h, at: h.clock)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0011"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(try records(h).first?.invoiceID == invoice.id.uuidString)
    }

    // A proposal (not an invoice) made for a visit bills nothing.
    @Test func aProposalForAVisitBillsNothing() throws {
        let h = try Harness(stopCount: 1)
        let visit = visit(h, at: h.clock)
        let proposal = Proposal(operatorID: "op", client: h.client)
        h.context.insert(proposal)
        visit.proposalID = proposal.id.uuidString
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        #expect(ServiceLog.isUnbilled(record, in: h.context))
        ServiceLog.markVisitInvoiced(visitID: visit.id.uuidString, invoice: proposal, in: h.context)
        #expect(ServiceLog.isUnbilled(record, in: h.context))
    }

    // An invoice deleted some other way (another device, an older PlowR)
    // leaves its ID behind: the work counts as unbilled, and saving from the
    // sheet can invoice it again and change its services.
    @Test func anInvoiceThatIsGoneDoesNotBillTheRecord() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let run = UUID()
        let record = ServiceLog.saveRecording(screen(h, selected: [clear]), notes: "", for: stop, of: h.client,
                                              run: run, operatorID: "op", startedAt: h.clock, in: h.context)
        record.invoiceID = UUID().uuidString
        #expect(ServiceLog.invoice(of: record, in: h.context) == nil)
        ServiceLog.saveRecording(screen(h, selected: [salt]), notes: "", for: stop, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(record.lines.map(\.name) == ["Salt"])
        #expect(ServiceLog.isUnbilled(record, in: h.context))
    }

    // A revision replaces the invoice: deleting the original afterwards
    // mustn't unbill work the revision bills.
    @Test func aRevisionTakesOverTheBilling() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let screen = screen(h, selected: [clear])
        let record = ServiceLog.saveRecording(screen, notes: "", for: stop, of: h.client, run: UUID(),
                                              operatorID: "op", startedAt: h.clock, in: h.context)
        let original = ServiceLog.invoice(record, lines: screen.invoiceLines, client: h.client, operatorID: "op",
                                          notes: "", now: h.clock, in: h.context)
        let revision = Proposal(operatorID: "op", client: h.client)
        revision.invoiceNumber = "INV-0001-R1"
        h.context.insert(revision)
        ServiceLog.moveBilling(from: original, to: revision, in: h.context)
        ServiceLog.delete(original, in: h.context)
        try h.context.save()
        #expect(record.invoiceID == revision.id.uuidString)
    }

    // Invoicing the day's visit from the sheet links the visit to the invoice,
    // so the Schedule doesn't offer to invoice it again.
    @Test func invoicingTheDaysVisitFromTheSheetLinksTheVisit() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let visit = visit(h, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let screen = screen(h, selected: [clear])
        let record = ServiceLog.saveRecording(screen, notes: "", for: stop, of: h.client,
                                              run: try #require(store.runID), operatorID: "op",
                                              startedAt: h.clock, in: h.context)
        let invoice = ServiceLog.invoice(record, lines: screen.invoiceLines, client: h.client, operatorID: "op",
                                         notes: "", now: h.clock, in: h.context)
        #expect(visit.proposalID == invoice.id.uuidString)
        #expect(invoice.visitID == visit.id.uuidString)
    }
    // MARK: - Second review

    private func invoice(_ h: Harness, _ number: String) -> Proposal {
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = number
        h.context.insert(invoice)
        return invoice
    }

    // Schedule → Invoice before the work, then Record Services on the route:
    // the driver's prices and custom items are kept (they used to be dropped
    // because the record counted as invoiced), and the sheet knows the
    // invoice before anything is saved, so it doesn't offer another.
    @Test func recordingAVisitInvoicedAheadKeepsTheDriversPrices() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let visit = visit(h, at: h.clock)
        let ahead = invoice(h, "INV-0020")
        visit.proposalID = ahead.id.uuidString
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let run = try #require(store.runID)
        #expect(ServiceLog.invoiceForStop(stop, of: h.client, run: run, startedAt: h.clock, in: h.context)?.id == ahead.id)

        var screen = screen(h, selected: [clear], typed: [clear.id.uuidString: "70"])
        screen.customItems = [.init(name: "Gate fix", price: "12")]
        let record = ServiceLog.saveRecording(screen, notes: "", for: stop, of: h.client, run: run,
                                              operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(record.lines.map(\.price) == [70, 12])
        #expect(record.invoiceID == ahead.id.uuidString)
    }

    // Reopening a record whose service was since switched off or deleted:
    // loaded and saved, nothing is lost or changed.
    @Test func loadingThenSavingChangesNothing() {
        let services: [StopRecording.Service] = [.init(id: "clear", name: "Clear", unitType: "flat", pricePerUnit: 40)]
        let lines = [ServiceRecord.Line(serviceID: "clear", name: "Clear", unitType: "flat", price: 55),
                     ServiceRecord.Line(serviceID: "gone", name: "Haul-away", unitType: "flat", price: 30),
                     ServiceRecord.Line(serviceID: "", name: "Gate fix", unitType: "flat", price: 12.5)]
        let loaded = StopRecording.loading(lines, services: services, zones: [])
        #expect(loaded.recordLines == lines)
        #expect(loaded.selectedIDs == ["clear"])
        #expect(loaded.keptLines.map(\.name) == ["Haul-away"])
        // The invoice has every line too.
        #expect(loaded.invoiceLines.map(\.lineTotal) == [55, 30, 12.5])
    }

    @Test func savingKeepsAServiceNoLongerInTheCatalog() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let run = UUID()
        let record = ServiceLog.saveRecording(screen(h, selected: [clear, salt]), notes: "", for: stop, of: h.client,
                                              run: run, operatorID: "op", startedAt: h.clock, in: h.context)
        salt.isActive = false
        let shown = [clear].map { StopRecording.Service(id: $0.id.uuidString, name: $0.name, unitType: $0.unitType,
                                                        pricePerUnit: $0.pricePerUnit) }
        let reopened = StopRecording.loading(record.lines, services: shown, zones: [])
        ServiceLog.saveRecording(reopened, notes: "Added a note", for: stop, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(record.lines.map(\.name) == ["Clear", "Salt"])
    }

    // Deleting an invoice frees its visit: the Schedule can invoice it again,
    // and a new invoice from the sheet links it.
    @Test func deletingAnInvoiceFreesItsVisit() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let visit = visit(h, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let run = try #require(store.runID)
        let screen = screen(h, selected: [clear])
        let record = ServiceLog.saveRecording(screen, notes: "", for: stop, of: h.client, run: run,
                                              operatorID: "op", startedAt: h.clock, in: h.context)
        let first = ServiceLog.invoice(record, lines: screen.invoiceLines, client: h.client, operatorID: "op",
                                       notes: "", now: h.clock, in: h.context)
        #expect(visit.proposalID == first.id.uuidString)
        ServiceLog.delete(first, in: h.context)
        try h.context.save()
        #expect(visit.proposalID == "")
        let second = ServiceLog.invoice(record, lines: screen.invoiceLines, client: h.client, operatorID: "op",
                                        notes: "", now: h.clock, in: h.context)
        #expect(visit.proposalID == second.id.uuidString)
    }

    // Deleting a revision (made by mistake) mustn't unbill work its original
    // invoice still bills.
    @Test func deletingARevisionBillsTheOriginalAgain() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let screen = screen(h, selected: [clear])
        let record = ServiceLog.saveRecording(screen, notes: "", for: stop, of: h.client, run: UUID(),
                                              operatorID: "op", startedAt: h.clock, in: h.context)
        let original = ServiceLog.invoice(record, lines: screen.invoiceLines, client: h.client, operatorID: "op",
                                          notes: "", now: h.clock, in: h.context)
        let revision = invoice(h, original.invoiceNumber + "-R1")
        revision.revisionOf = original.invoiceNumber
        ServiceLog.moveBilling(from: original, to: revision, in: h.context)
        ServiceLog.delete(revision, in: h.context)
        try h.context.save()
        #expect(record.invoiceID == original.id.uuidString)
        #expect(!ServiceLog.isUnbilled(record, in: h.context))
    }

    // Reopened from the recap after midnight and saved: still the stop's one
    // record (found by run and stop), not a second.
    @Test func savingACompletedStopAfterMidnightIsTheSameRecord() throws {
        let h = try Harness(stopCount: 2)
        let (clear, _) = services(h)
        _ = visit(h, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let run = try #require(store.runID)
        store.completeShownStop()
        let nextDay = Calendar.current.startOfDay(for: h.clock).addingTimeInterval(86_400 + 600)
        ServiceLog.saveRecording(screen(h, selected: [clear]), notes: "", for: stop, of: h.client, run: run,
                                 operatorID: "op", startedAt: nextDay, in: h.context)
        #expect(try records(h).count == 1)
    }

    // A client on a route twice, with one visit that day: the visit is the
    // first stop's; the second stop's work is its own record, not an
    // overwrite of the first's.
    @Test func aClientTwiceOnARouteDoesNotShareOneRecord() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = services(h)
        let again = RouteStop(order: 1, client: h.client)
        again.route = h.route
        h.context.insert(again)
        let visit = visit(h, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStop)
        let run = try #require(store.runID)
        ServiceLog.saveRecording(screen(h, selected: [clear]), notes: "", for: first, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        ServiceLog.saveRecording(screen(h, selected: [salt]), notes: "", for: again, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        let all = try records(h).sorted { $0.lines.first?.name ?? "" < $1.lines.first?.name ?? "" }
        #expect(all.count == 2)
        #expect(all.map(\.visitID) == [visit.id.uuidString, ""])
    }
    // MARK: - Third review

    // Revised from either page (both go through `revise`): the revision
    // bills the work and holds the visit, so deleting the superseded
    // original frees neither.
    @Test func aRevisionHoldsTheVisitWhenTheOriginalIsDeleted() throws {
        let h = try Harness(stopCount: 1)
        let visit = visit(h, at: h.clock)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        let original = invoice(h, "INV-0030")
        visit.proposalID = original.id.uuidString
        original.visitID = visit.id.uuidString
        ServiceLog.markVisitInvoiced(visitID: visit.id.uuidString, invoice: original, in: h.context)
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        #expect(revision.revisionOf == "INV-0030")
        #expect(record.invoiceID == revision.id.uuidString)
        #expect(visit.proposalID == revision.id.uuidString)
        #expect(revision.visitID == visit.id.uuidString)

        ServiceLog.delete(original, in: h.context)
        try h.context.save()
        #expect(visit.proposalID == revision.id.uuidString)
        #expect(!ServiceLog.isUnbilled(record, in: h.context))
    }

    // Deleting the revision instead hands the visit back to the original.
    @Test func deletingARevisionHandsTheVisitBack() throws {
        let h = try Harness(stopCount: 1)
        let visit = visit(h, at: h.clock)
        let original = invoice(h, "INV-0031")
        visit.proposalID = original.id.uuidString
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        ServiceLog.delete(revision, in: h.context)
        try h.context.save()
        #expect(visit.proposalID == original.id.uuidString)
    }

    // Recorded on one run but never completed, then run again: the second
    // run takes the visit over and completes it, one record.
    @Test func aVisitRecordedButNotCompletedIsTakenOverByTheNextRun() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let visit = visit(h, at: h.clock)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        ServiceLog.saveRecording(screen(h, selected: [clear]), notes: "", for: try #require(store.currentStop),
                                 of: h.client, run: try #require(store.runID), operatorID: "op",
                                 startedAt: h.clock, in: h.context)
        store.end()
        h.clock = h.clock.addingTimeInterval(60)
        store.start(h.route)
        store.completeShownStop()
        #expect(visit.status == .completed)
        let all = try records(h)
        #expect(all.count == 1)
        #expect(all.first?.runID == store.runID?.uuidString)
    }

    // Services recorded at the wrong stop can be cleared.
    @Test func savingAnEmptySheetClearsTheRecord() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = services(h)
        let stop = try #require(h.route.sortedStops.first)
        let run = UUID()
        let record = ServiceLog.saveRecording(screen(h, selected: [clear]), notes: "", for: stop, of: h.client,
                                              run: run, operatorID: "op", startedAt: h.clock, in: h.context)
        ServiceLog.saveRecording(screen(h, selected: []), notes: "", for: stop, of: h.client, run: run,
                                 operatorID: "op", startedAt: h.clock, in: h.context)
        #expect(record.lines.isEmpty)
        #expect(stop.completedServiceIDs.isEmpty)
    }

    // The run's start survives a relaunch, not just the current stop's.
    @Test func theRunsStartSurvivesARelaunch() throws {
        let h = try Harness(stopCount: 2)
        let before = h.makeClosedAppStore()
        before.start(h.route)
        let started = try #require(before.runStartedAt)
        h.clock = h.clock.addingTimeInterval(30 * 60)
        before.completeShownStop()
        let after = h.makeStore()
        #expect(after.runStartedAt == started)
        #expect(after.stopStartedAt != started)
    }
}
