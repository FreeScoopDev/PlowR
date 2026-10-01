//
//  ContractInstallmentsTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A contract's own payments: their schedule, and the draft invoices made
/// on their dates, once.
@MainActor
struct ContractInstallmentsTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? .distantPast
    }

    private func contract(_ h: Harness, _ pricing: Contracts.Pricing, price: Double, installments: Int = 1,
                          from start: Date, to end: Date, signed: Bool = true) -> Contract {
        let contract = Contract(name: "Winter", startDate: start, endDate: end, operatorID: "op")
        contract.pricingRaw = pricing.rawValue
        contract.price = price
        contract.installments = installments
        contract.serviceIDs = ["plow"]
        contract.placeIDs = [h.client.id.uuidString]
        contract.clientID = h.client.id.uuidString
        h.context.insert(contract)
        contract.client = h.client
        if signed { contract.signedAt = start }
        return contract
    }

    @Test func aSeasonPriceIsSplitIntoMonthlyPaymentsToTheCent() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h, .season, price: 100, installments: 3, from: date(2026, 11, 15), to: date(2027, 4, 15))
        let schedule = ContractInstallments.schedule(of: season, calendar: calendar)
        #expect(schedule.map(\.amount) == [33.33, 33.33, 33.34])
        #expect(schedule.map(\.date) == [date(2026, 11, 15), date(2026, 12, 15), date(2027, 1, 15)])
        #expect(ContractInstallments.title(of: schedule[1], in: season) == "Winter, payment 2 of 3")
        season.price = 199
        season.installments = 5
        #expect(ContractInstallments.schedule(of: season, calendar: calendar).map(\.amount) == [39.8, 39.8, 39.8, 39.8, 39.8])
        season.installments = 1
        season.price = 100
        #expect(ContractInstallments.schedule(of: season, calendar: calendar).map(\.amount) == [100])
    }

    @Test func aMonthlyContractBillsEachMonthThroughItsEnd() throws {
        let h = try Harness(stopCount: 0)
        let lawn = contract(h, .monthly, price: 160, from: date(2027, 4, 1), to: date(2027, 9, 1))
        let schedule = ContractInstallments.schedule(of: lawn, calendar: calendar)
        #expect(schedule.count == 6)                                              // its last day counts
        #expect(schedule.allSatisfy { $0.amount == 160 })
        #expect(schedule.last?.date == date(2027, 9, 1))
        #expect(ContractInstallments.title(of: schedule[0], in: lawn, calendar: calendar) == "Winter, April 2027")
        let perVisit = contract(h, .perVisit, price: 55, from: date(2027, 4, 1), to: date(2027, 9, 30))
        #expect(ContractInstallments.schedule(of: perVisit, calendar: calendar).isEmpty)
    }

    // Counted from the start each month: the 31st stays at the month's end.
    @Test func paymentsFromThe31stStayAtTheMonthsEnd() throws {
        let h = try Harness(stopCount: 0)
        let lawn = contract(h, .monthly, price: 160, from: date(2027, 1, 31), to: date(2027, 4, 30))
        #expect(ContractInstallments.schedule(of: lawn, calendar: calendar).map(\.date)
                == [date(2027, 1, 31), date(2027, 2, 28), date(2027, 3, 31), date(2027, 4, 30)])
    }

    // On its date a payment is due; Make Invoice makes its draft, once.
    @Test func aPaymentIsDueOnItsDateAndItsInvoiceIsMadeOnce() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h, .season, price: 900, installments: 3, from: date(2026, 11, 15), to: date(2027, 4, 15))
        #expect(ContractInstallments.due(season, now: date(2026, 11, 14, 12), calendar: calendar).isEmpty)
        let due = ContractInstallments.due(season, now: date(2026, 11, 15, 8), calendar: calendar)
        #expect(due.map(\.index) == [1])
        let invoice = try #require(ContractInstallments.makeInvoice(for: due[0], of: season, in: h.context,
                                                                     now: date(2026, 11, 15, 8), calendar: calendar))
        #expect(invoice.isInvoice && invoice.invoiceStatus == .draft)
        #expect(invoice.total == 300)
        #expect(invoice.contractID == season.id.uuidString && invoice.installmentIndex == 1)
        #expect(invoice.invoiceDueDate == nil)                                    // set when it's sent
        #expect(ContractInstallments.makeInvoice(for: due[0], of: season, in: h.context) == nil)
        #expect(ContractInstallments.due(season, now: date(2026, 11, 20), calendar: calendar).isEmpty)
        // Deleted on purpose: not due again.
        h.context.delete(invoice)
        try h.context.save()
        #expect(ContractInstallments.due(season, now: date(2026, 11, 21), calendar: calendar).isEmpty)
        // Away a while: everything since is due.
        #expect(ContractInstallments.due(season, now: date(2027, 2, 1), calendar: calendar).map(\.index) == [2, 3])
        // Sent: due 30 days from sending, not from when the draft was made.
        let second = try #require(ContractInstallments.makeInvoice(
            for: ContractInstallments.due(season, now: date(2027, 2, 1), calendar: calendar)[0], of: season,
            in: h.context, now: date(2027, 2, 1), calendar: calendar))
        DocumentSent.markSent(second, in: h.context, now: date(2027, 3, 1))
        #expect(second.invoiceDueDate == date(2027, 3, 1).addingTimeInterval(30 * 86_400))
    }

    @Test func aDraftOrACancelledContractIsntDue() throws {
        let h = try Harness(stopCount: 0)
        let unsigned = contract(h, .monthly, price: 160, from: date(2027, 4, 1), to: date(2027, 9, 30), signed: false)
        #expect(ContractInstallments.due(unsigned, now: date(2027, 6, 1), calendar: calendar).isEmpty)
        let lawn = contract(h, .monthly, price: 160, from: date(2027, 4, 1), to: date(2027, 9, 30))
        lawn.cancelledAt = date(2027, 5, 10, 15)
        #expect(ContractInstallments.due(lawn, now: date(2027, 8, 1), calendar: calendar).map(\.index) == [1, 2])
        lawn.client = nil                                                         // kept after the client was deleted
        #expect(ContractInstallments.due(lawn, now: date(2027, 8, 1), calendar: calendar).isEmpty)
    }

    @Test func makeInvoicesMakesEverythingDueForThisBusiness() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h, .season, price: 900, installments: 3, from: date(2026, 11, 15), to: date(2027, 4, 15))
        let theirs = contract(h, .monthly, price: 100, from: date(2026, 11, 1), to: date(2027, 4, 1))
        theirs.operatorID = "someone-else"
        let now = date(2026, 12, 20)
        #expect(ContractInstallments.allDue([season, theirs], operatorID: "op", now: now, calendar: calendar).count == 2)
        let made = ContractInstallments.makeAllDue(operatorID: "op", in: h.context, now: now)
        #expect(made.count == 2)
        let documents = try h.context.fetch(FetchDescriptor<Proposal>())
        #expect(ContractInstallments.readyToSend(documents, operatorID: "op").count == 2)
        DocumentSent.markSent(made[0], in: h.context, now: now)
        #expect(ContractInstallments.readyToSend(documents, operatorID: "op").count == 1)
    }

    // A revised payment invoice is still that payment, and the page shows the revision.
    @Test func aRevisionIsStillThePayment() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h, .season, price: 900, installments: 3, from: date(2026, 11, 15), to: date(2027, 4, 15))
        let now = date(2026, 11, 15, 9)
        let original = try #require(ContractInstallments.makeInvoice(
            for: ContractInstallments.due(season, now: now, calendar: calendar)[0], of: season, in: h.context, now: now))
        let revision = ServiceLog.revise(original, client: h.client, in: h.context)
        #expect(revision.contractID == season.id.uuidString && revision.installmentIndex == 1)
        #expect(ContractInstallments.ledger(of: season, in: h.context, calendar: calendar).first?.invoice?.id == revision.id)
    }

    @Test func seasonPaymentsHaveToFitItsPeriod() throws {
        let h = try Harness(stopCount: 0)
        var draft = Contracts.Draft(for: h.client, now: date(2026, 11, 1))
        draft.priceText = "900"
        draft.serviceIDs = ["plow"]
        draft.installments = 6                                                    // Nov … Apr, inside Nov 1 – Apr 30
        #expect(draft.problem(now: date(2026, 11, 1), calendar: calendar) == nil)
        draft.installments = 7
        #expect(draft.problem(now: date(2026, 11, 1), calendar: calendar)?.hasPrefix("Its 7 monthly payments") == true)
    }
}
