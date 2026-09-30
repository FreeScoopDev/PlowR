//
//  ServiceHistoryTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A client's Service History: work logged by hand, a job corrected on its
/// own page, and deleting one. Invoiced work keeps matching its bill.
@MainActor
struct ServiceHistoryTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func catalog(_ h: Harness) -> (clear: ServiceItem, salt: ServiceItem) {
        let clear = ServiceItem(name: "Clear", category: "snow", unitType: "flat", pricePerUnit: 40,
                                operatorID: "op", sortOrder: 0)
        let salt = ServiceItem(name: "Salt", category: "snow", unitType: "flat", pricePerUnit: 10,
                               operatorID: "op", sortOrder: 1)
        h.context.insert(clear)
        h.context.insert(salt)
        return (clear, salt)
    }

    private func form(_ services: [ServiceItem], selected: [ServiceItem],
                      custom: [StopRecording.CustomItem] = []) -> StopRecording {
        StopRecording(services: ServiceLog.activeServices(services, operatorID: "op"), zones: [],
                      selectedIDs: Set(selected.map(\.id.uuidString)), customItems: custom)
    }

    @Test func workLoggedByHandIsAManualRecord() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = catalog(h)
        let done = h.clock.addingTimeInterval(-3_600)
        let record = ServiceLog.logWork(form([clear, salt], selected: [salt], custom: [.init(name: "Haul", price: "25")]),
                                        notes: "Call-out", performedAt: done, minutes: 30, for: h.client,
                                        operatorID: "op", now: h.clock, in: h.context)
        #expect(record.source == .manual)
        #expect(record.sourceKey.hasPrefix("manual:"))
        #expect(record.clientID == h.client.id.uuidString)
        #expect(record.propertyAddress == h.client.address)
        #expect(record.performedAt == done)
        #expect(record.minutes == 30)
        #expect(record.lines.map(\.name) == ["Salt", "Haul"])
        #expect(ServiceLog.total(of: record) == 35)
        #expect(record.notes == "Call-out")
        #expect(ServiceLog.isUnbilled(record, in: h.context))
    }

    // Two jobs logged by hand are two records, never one.
    @Test func eachLoggedJobIsItsOwnRecord() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = catalog(h)
        for _ in 0..<2 {
            ServiceLog.logWork(form([clear], selected: [clear]), notes: "", performedAt: h.clock, minutes: 0,
                               for: h.client, operatorID: "op", in: h.context)
        }
        #expect(try h.context.fetch(FetchDescriptor<ServiceRecord>()).count == 2)
    }

    // A comped client's hand-logged work isn't billable either.
    @Test func workLoggedForACompedClientIsNoCharge() throws {
        let h = try Harness(stopCount: 1)
        h.client.isComped = true
        let record = ServiceLog.logWork(StopRecording(services: [], zones: []), notes: "n", performedAt: h.clock,
                                        minutes: 0, for: h.client, operatorID: "op", in: h.context)
        #expect(!record.isBillable)
        #expect(!ServiceLog.isUnbilled(record, in: h.context))
    }

    @Test func aJobCanBeCorrected() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = catalog(h)
        let record = ServiceLog.logWork(form([clear, salt], selected: [clear]), notes: "", performedAt: h.clock,
                                        minutes: 10, for: h.client, operatorID: "op", in: h.context)
        let later = h.clock.addingTimeInterval(600)
        ServiceLog.update(record, lines: form([clear, salt], selected: [salt]).recordLines, notes: "Fixed",
                          performedAt: later, minutes: 25, isBillable: false, now: later, in: h.context)
        #expect(record.lines.map(\.name) == ["Salt"])
        #expect(record.notes == "Fixed")
        #expect(record.performedAt == later)
        #expect(record.minutes == 25)
        #expect(!record.isBillable)
    }

    // On an invoice, a job's services and billable-ness are what the bill
    // says; the date, time and notes can still be corrected.
    @Test func anInvoicedJobKeepsItsServicesAndBilling() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = catalog(h)
        let first = form([clear, salt], selected: [clear])
        let record = ServiceLog.logWork(first, notes: "", performedAt: h.clock, minutes: 10, for: h.client,
                                        operatorID: "op", in: h.context)
        ServiceLog.invoice(record, lines: first.invoiceLines, client: h.client, operatorID: "op", notes: "",
                           now: h.clock, in: h.context)
        ServiceLog.update(record, lines: form([clear, salt], selected: [salt]).recordLines, notes: "Late note",
                          performedAt: h.clock, minutes: 12, isBillable: false, in: h.context)
        #expect(record.lines.map(\.name) == ["Clear"])
        #expect(record.isBillable)
        #expect(record.notes == "Late note")
        #expect(record.minutes == 12)
    }

    @Test func deletingAJobKeepsItsPhotosInTheGallery() throws {
        let h = try Harness(stopCount: 1)
        let record = ServiceLog.logWork(StopRecording(services: [], zones: []), notes: "n", performedAt: h.clock,
                                        minutes: 0, for: h.client, operatorID: "op", in: h.context)
        let photo = StopPhoto(operatorID: "op", clientID: h.client.id.uuidString, routeID: "", isBefore: true,
                              imageData: Data([1]))
        photo.recordID = record.id.uuidString
        h.context.insert(photo)
        #expect(ServiceLog.photos(of: record, in: h.context).map(\.id) == [photo.id])

        #expect(ServiceLog.deleteRecord(record, in: h.context))
        try h.context.save()
        #expect(try h.context.fetch(FetchDescriptor<ServiceRecord>()).isEmpty)
        #expect(try h.context.fetch(FetchDescriptor<StopPhoto>()).count == 1)
        #expect(photo.recordID == "")
    }

    // Invoiced work can't be deleted: the bill would name work the log no
    // longer has. Delete the invoice first.
    @Test func anInvoicedJobCantBeDeleted() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = catalog(h)
        let screen = form([clear], selected: [clear])
        let record = ServiceLog.logWork(screen, notes: "", performedAt: h.clock, minutes: 0, for: h.client,
                                        operatorID: "op", in: h.context)
        let invoice = ServiceLog.invoice(record, lines: screen.invoiceLines, client: h.client, operatorID: "op",
                                         notes: "", now: h.clock, in: h.context)
        #expect(!ServiceLog.deleteRecord(record, in: h.context))
        ServiceLog.delete(invoice, in: h.context)
        #expect(ServiceLog.deleteRecord(record, in: h.context))
    }

    @Test func theFormsListOnlyActiveServicesInCatalogOrder() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = catalog(h)
        clear.sortOrder = 5
        let off = ServiceItem(name: "Edging", category: "lawn", unitType: "flat", pricePerUnit: 15, operatorID: "op")
        off.isActive = false
        let theirs = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 30,
                                 operatorID: "someone else")
        let names = ServiceLog.activeServices([clear, salt, off, theirs], operatorID: "op").map(\.name)
        #expect(names == ["Salt", "Clear"])
    }
    // A service renamed in the catalog since: the job keeps the name the work
    // was done under, even when it's saved for something else.
    @Test func aJobKeepsAServicesOldName() throws {
        let h = try Harness(stopCount: 1)
        let (clear, salt) = catalog(h)
        let record = ServiceLog.logWork(form([clear, salt], selected: [clear]), notes: "", performedAt: h.clock,
                                        minutes: 0, for: h.client, operatorID: "op", in: h.context)
        clear.name = "Clearing"
        let reopened = StopRecording.loading(record.lines, services: ServiceLog.activeServices([clear, salt],
                                                                                                operatorID: "op"),
                                             zones: [])
        #expect(reopened.keptLines.map(\.name) == ["Clear"])
        ServiceLog.update(record, lines: reopened.recordLines, notes: "Typo fixed", performedAt: record.performedAt,
                          minutes: 0, isBillable: true, in: h.context)
        #expect(record.lines.map(\.name) == ["Clear"])
    }

    // On an invoice made before the work (a visit invoiced ahead), a job with
    // no services yet can be given them; billable still can't change.
    @Test func aJobInvoicedAheadCanBeGivenItsServices() throws {
        let h = try Harness(stopCount: 1)
        let (clear, _) = catalog(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0040"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        #expect(record.lines.isEmpty)
        #expect(!ServiceLog.servicesLocked(record, in: h.context))
        ServiceLog.update(record, lines: form([clear], selected: [clear]).recordLines, notes: "",
                          performedAt: record.performedAt, minutes: 0, isBillable: false, in: h.context)
        #expect(record.lines.map(\.name) == ["Clear"])
        #expect(record.isBillable)
    }

    @Test func aJobIsNeverDatedInTheFuture() throws {
        let h = try Harness(stopCount: 1)
        let tomorrow = h.clock.addingTimeInterval(86_400)
        let record = ServiceLog.logWork(StopRecording(services: [], zones: []), notes: "n", performedAt: tomorrow,
                                        minutes: 0, for: h.client, operatorID: "op", now: h.clock, in: h.context)
        #expect(record.performedAt == h.clock)
        ServiceLog.update(record, lines: [], notes: "n", performedAt: tomorrow, minutes: 0, isBillable: true,
                          now: h.clock, in: h.context)
        #expect(record.performedAt == h.clock)
    }
}
