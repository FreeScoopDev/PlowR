//
//  WorkBillingTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Bill Unbilled Work: each client's jobs not billed yet in a period, and one
/// draft invoice per client for them.
@MainActor
struct WorkBillingTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func job(_ h: Harness, _ client: Client, at date: Date, _ lines: [(String, Double)],
                     source: ServiceRecordSource = .manual, billable: Bool = true) -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: "k:\(UUID())", source: source)
        record.clientID = client.id.uuidString
        record.performedAt = date
        record.propertyAddress = client.address
        record.isBillable = billable
        record.lines = lines.map { ServiceRecord.Line(serviceID: $0.0, name: $0.0, unitType: "flat", price: $0.1) }
        h.context.insert(record)
        return record
    }

    @Test func onlyUnbilledWorkIsListedByClient() throws {
        let h = try Harness(stopCount: 3)
        let (pat, sam, lee) = (h.clients[0], h.clients[1], h.clients[2])
        pat.name = "Pat"; sam.name = "Sam"; lee.name = "Lee"
        let later = job(h, pat, at: h.clock, [("Clear", 40)])
        let earlier = job(h, pat, at: h.clock.addingTimeInterval(-86_400), [("Salt", 10), ("Clear", 40)])
        _ = job(h, sam, at: h.clock, [("Clear", 55)])
        _ = job(h, lee, at: h.clock, [("Clear", 40)], billable: false)             // no charge
        _ = job(h, lee, at: h.clock, [("Clear", 40)], source: .beforeLog)           // billing not tracked
        _ = job(h, lee, at: h.clock, [])                                            // nothing to bill
        let billed = job(h, sam, at: h.clock, [("Salt", 10)])
        let invoice = Proposal(operatorID: "op", client: sam)
        invoice.invoiceNumber = "INV-0001"
        h.context.insert(invoice)
        billed.invoiceID = invoice.id.uuidString

        let works = WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context)
        #expect(works.map(\.client.name) == ["Pat", "Sam"])
        #expect(works[0].records.map(\.id) == [earlier.id, later.id])
        #expect(works[0].total == 90)
        #expect(works[1].total == 55)
    }

    @Test func thePeriodLimitsTheWork() throws {
        let h = try Harness(stopCount: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12)))
        let thisMonth = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)))
        let lastMonth = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        let older = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3)))
        // One this month, two last month, one before: each period's count differs.
        for date in [thisMonth, lastMonth, lastMonth, older] { _ = job(h, h.client, at: date, [("Clear", 40)]) }
        func count(_ period: WorkBilling.Period) -> Int {
            WorkBilling.unbilledWork(in: period.range(now: now, calendar: calendar), operatorID: "op",
                                     in: h.context).first?.records.count ?? 0
        }
        #expect(count(.thisMonth) == 1)
        #expect(count(.lastMonth) == 2)
        #expect(count(.everything) == 4)
    }

    // One invoice for a client's jobs: a line per service, oldest job first,
    // the day under each; every job billed on it, so it's not billed twice.
    @Test func aClientsJobsBecomeOneDraftInvoice() throws {
        let h = try Harness(stopCount: 1)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultDisclaimer = "Payment due in 30 days."
        h.context.insert(profile)
        _ = job(h, h.client, at: h.clock, [("Clear", 40)])
        let first = job(h, h.client, at: h.clock.addingTimeInterval(-86_400), [("Salt", 10.5), ("Clear", 40)])
        let expectedDay = WorkBilling.day(first.performedAt, now: h.clock)
        first.propertyAddress = "9 Lot Rd"
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)

        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.isInvoice)
        #expect(invoice.invoiceSentAt == nil)
        #expect(invoice.total == 90.5)
        #expect(invoice.sortedLineItems.map(\.serviceName) == ["Salt", "Clear", "Clear"])
        #expect(invoice.sortedLineItems[0].itemNotes == expectedDay + " · 9 Lot Rd")
        #expect(!invoice.sortedLineItems[2].itemNotes.contains("·"))
        #expect(invoice.disclaimer == "Payment due in 30 days.")
        #expect(invoice.invoiceDueDate == h.clock.addingTimeInterval(30 * 86_400))
        #expect(work.records.allSatisfy { $0.invoiceID == invoice.id.uuidString })
        #expect(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).isEmpty)

        // Deleting it makes the work unbilled again (ServiceLog.delete).
        ServiceLog.delete(invoice, in: h.context)
        #expect(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first?.records.count == 2)
    }

    // A billed visit is linked, so the Schedule doesn't offer to invoice it.
    @Test func aBilledVisitIsLinked() throws {
        let h = try Harness(stopCount: 1)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = job(h, h.client, at: h.clock, [("Clear", 40)], source: .visit)
        record.visitID = visit.id.uuidString
        record.sourceKey = ServiceLog.visitKey(visit.id)        // as a visit's record is
        #expect(!ServiceLog.isVisitBilled(visit, in: h.context))
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(visit.proposalID == invoice.id.uuidString)
        #expect(ServiceLog.isVisitBilled(visit, in: h.context))
    }

    // Several clients at once: each its own invoice, with its own number.
    @Test func eachClientsInvoiceHasItsOwnNumber() throws {
        let h = try Harness(stopCount: 3)
        for client in h.clients { _ = job(h, client, at: h.clock, [("Clear", 40)]) }
        let works = WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context)
        let outcome = WorkBilling.invoiceAll(works, operatorID: "op", now: h.clock, in: h.context)
        let invoices = outcome.invoices
        #expect(!outcome.stoppedShort)
        #expect(invoices.count == 3)
        #expect(Set(invoices.map(\.invoiceNumber)).count == 3)
        #expect(Set(invoices.map(\.clientID)) == Set(h.clients.map(\.id.uuidString)))
    }

    // The same job recorded on two devices before they synced: one job, one
    // set of lines, and both copies billed.
    @Test func theSameJobFromTwoDevicesIsBilledOnce() throws {
        let h = try Harness(stopCount: 1)
        let key = ServiceLog.visitKey(UUID())
        // The newer copy is made first, so the order found can't stand in for age.
        let newer = job(h, h.client, at: h.clock, [("Clear", 40)], source: .route)
        newer.sourceKey = key
        newer.createdAt = h.clock.addingTimeInterval(5)
        let older = job(h, h.client, at: h.clock, [("Clear", 40)], source: .visit)
        older.sourceKey = key
        older.createdAt = h.clock
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        #expect(work.records.map(\.id) == [older.id])
        #expect(work.total == 40)
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.total == 40)
        #expect(newer.invoiceID == invoice.id.uuidString)
    }

    // One copy already invoiced (Record Services on the other device): the
    // job isn't billed again.
    @Test func aJobWithACopyAlreadyInvoicedIsLeftOut() throws {
        let h = try Harness(stopCount: 1)
        let key = ServiceLog.visitKey(UUID())
        let unbilled = job(h, h.client, at: h.clock, [("Clear", 40)], source: .visit)
        unbilled.sourceKey = key
        let billedCopy = job(h, h.client, at: h.clock, [("Clear", 40)], source: .route)
        billedCopy.sourceKey = key
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0009"
        h.context.insert(invoice)
        billedCopy.invoiceID = invoice.id.uuidString
        #expect(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).isEmpty)
    }

    // Billed elsewhere after the list was made: left off, and with nothing
    // left there's no invoice.
    @Test func workBilledSinceTheListWasMadeIsLeftOff() throws {
        let h = try Harness(stopCount: 1)
        let a = job(h, h.client, at: h.clock, [("Clear", 40)])
        let b = job(h, h.client, at: h.clock.addingTimeInterval(60), [("Salt", 10)])
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        let elsewhere = Proposal(operatorID: "op", client: h.client)
        elsewhere.invoiceNumber = "INV-0050"
        h.context.insert(elsewhere)
        a.invoiceID = elsewhere.id.uuidString

        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.sortedLineItems.map(\.serviceName) == ["Salt"])
        #expect(a.invoiceID == elsewhere.id.uuidString)
        #expect(b.invoiceID == invoice.id.uuidString)
        #expect(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context) == nil)
    }

    @Test func otherOperatorsWorkAndGoneClientsAreLeftOut() throws {
        let h = try Harness(stopCount: 2)
        let theirs = job(h, h.clients[0], at: h.clock, [("Clear", 40)])
        theirs.operatorID = "someone else"
        _ = job(h, h.clients[1], at: h.clock, [("Clear", 40)])
        h.context.delete(h.clients[1])
        try h.context.save()
        #expect(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).isEmpty)
    }

    // A visit linked to a document since deleted is linked to the new invoice.
    @Test func aVisitWithADeletedDocumentIsRelinked() throws {
        let h = try Harness(stopCount: 1)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        visit.proposalID = UUID().uuidString
        h.context.insert(visit)
        let record = job(h, h.client, at: h.clock, [("Clear", 40)], source: .visit)
        record.visitID = visit.id.uuidString
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(visit.proposalID == invoice.id.uuidString)
    }

    @Test func aDayFromAnotherYearHasItsYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15)))
        let thisYear = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 4)))
        let lastYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 11, day: 12)))
        #expect(!WorkBilling.day(thisYear, now: now, calendar: calendar).contains("2026"))
        #expect(WorkBilling.day(lastYear, now: now, calendar: calendar).contains("2025"))
    }

    // Record Services' invoice gets the business's default terms too (both
    // go through ServiceLog.newDraftInvoice).
    @Test func recordServicesInvoicesUseTheDefaultTerms() throws {
        let h = try Harness(stopCount: 1)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultDisclaimer = "Net 30."
        h.context.insert(profile)
        let record = job(h, h.client, at: h.clock, [("Clear", 40)])
        let invoice = ServiceLog.invoice(record, lines: [], client: h.client, operatorID: "op", notes: "",
                                         now: h.clock, in: h.context)
        #expect(invoice.disclaimer == "Net 30.")
        #expect(invoice.invoiceDueDate == h.clock.addingTimeInterval(ServiceLog.invoiceTerm))
    }

    // The office ticked the visit off with its usual services, the crew
    // recorded what was done: billing either now could bill the wrong ones,
    // so the job waits for the merge.
    @Test func copiesThatDisagreeWaitForTheMerge() throws {
        let h = try Harness(stopCount: 1)
        let key = ServiceLog.visitKey(UUID())
        let office = job(h, h.client, at: h.clock, [("Clear", 40)], source: .visit)
        office.sourceKey = key
        let crew = job(h, h.client, at: h.clock, [("Clear", 40), ("Salt", 10)], source: .route)
        crew.sourceKey = key
        crew.startedAt = h.clock
        #expect(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).isEmpty)
    }

    // Deleted since the list was made: not billed.
    @Test func workDeletedSinceTheListWasMadeIsLeftOff() throws {
        let h = try Harness(stopCount: 1)
        let gone = job(h, h.client, at: h.clock, [("Clear", 40)])
        _ = job(h, h.client, at: h.clock.addingTimeInterval(60), [("Salt", 10)])
        try h.context.save()
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        h.context.delete(gone)
        try h.context.save()
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.sortedLineItems.map(\.serviceName) == ["Salt"])
    }

    @Test func oneClientsWorkCanBeAskedFor() throws {
        let h = try Harness(stopCount: 2)
        for client in h.clients { _ = job(h, client, at: h.clock, [("Clear", 40)]) }
        let works = WorkBilling.unbilledWork(in: nil, operatorID: "op", clientID: h.clients[1].id.uuidString,
                                             in: h.context)
        #expect(works.map(\.client.id) == [h.clients[1].id])
    }

    // A service priced by the square foot recorded at $0 (no measured area,
    // done from a route or the Schedule) is pointed out, not billed unseen.
    @Test func aJobWithAnUnpricedServiceIsPointedOut() throws {
        let h = try Harness(stopCount: 1)
        let pat = h.clients[0]
        let record = job(h, pat, at: h.clock, [("Edge", 45)])
        record.lines.append(ServiceRecord.Line(serviceID: "mow", name: "Mowing", unitType: "perSqFt", price: 0))
        _ = job(h, pat, at: h.clock.addingTimeInterval(-86_400), [("Edge", 45)])
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        #expect(work.jobsNeedingAPrice == 1 && work.total == 90)
        // Priced, it isn't.
        record.lines = record.lines.map { line in
            var line = line
            if line.unitType == "perSqFt" { line.price = 60 }
            return line
        }
        let priced = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        #expect(priced.jobsNeedingAPrice == 0 && priced.total == 150)
    }
}

