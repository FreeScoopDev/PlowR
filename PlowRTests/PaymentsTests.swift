//
//  PaymentsTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The payments ledger: invoices paid in parts or all at once, what's owed
/// and what came in, the same everywhere they're shown.
@MainActor
struct PaymentsTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func invoice(_ h: Harness, total: Double, number: String = "INV-0001") -> Proposal {
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = number
        invoice.invoiceSentAt = h.clock.addingTimeInterval(-86_400)
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        h.context.insert(item)
        h.context.insert(invoice)
        invoice.lineItems = [item]
        return invoice
    }

    // MARK: - Paid in parts

    @Test func anInvoiceIsPaidOnceItsPaymentsCoverIt() throws {
        let h = try Harness(stopCount: 0)
        h.client.lastMessageSentAt = h.clock.addingTimeInterval(-86_400)          // awaiting a response
        let bill = invoice(h, total: 100)
        let first = try #require(Payments.record(30, method: "Cash", receivedAt: h.clock.addingTimeInterval(-3_600),
                                                 on: bill, in: h.context, now: h.clock))
        #expect(first.clientID == h.client.id.uuidString)
        #expect(bill.amountPaid == 30)
        #expect(bill.balanceDue == 70)
        #expect(bill.isPartlyPaid)
        #expect(bill.invoicePaidAt == nil)
        #expect(bill.invoiceStatus == .sent)
        #expect(h.client.clientRespondedAt == nil)                                // part isn't the response

        Payments.record(70, method: "Check", note: "#1042", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        #expect(bill.invoicePaidAt == h.clock)                                    // the day the last part came
        #expect(bill.balanceDue == 0)
        #expect(!bill.isPartlyPaid)
        #expect(bill.invoiceStatus == .paid)
        #expect(h.client.clientRespondedAt == h.clock)                            // paid: they've responded
        #expect(bill.sortedPayments.map(\.note) == ["", "#1042"])
    }

    @Test func onlyWhatsOwedCanBeRecorded() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        #expect(Payments.record(0, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock) == nil)
        #expect(Payments.record(100.01, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock) == nil)
        let quote = Proposal(operatorID: "op", client: h.client)
        h.context.insert(quote)
        #expect(Payments.record(10, method: "", receivedAt: h.clock, on: quote, in: h.context, now: h.clock) == nil)
        let later = Payments.record(10, method: "", receivedAt: h.clock.addingTimeInterval(86_400), on: bill,
                                    in: h.context, now: h.clock)
        #expect(later?.receivedAt == h.clock)                                     // never in the future
    }

    @Test func takingAPaymentBackMakesItOwedAgain() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        let part = try #require(Payments.record(40, method: "", receivedAt: h.clock, on: bill, in: h.context,
                                                now: h.clock))
        let rest = try #require(Payments.record(60, method: "", receivedAt: h.clock, on: bill, in: h.context,
                                                now: h.clock))
        #expect(bill.invoicePaidAt != nil)
        Payments.delete(rest, in: h.context)
        #expect(bill.invoicePaidAt == nil)
        #expect(bill.balanceDue == 60)
        Payments.delete(part, in: h.context)                                      // the last one
        #expect(bill.invoicePaidAt == nil)
        #expect(bill.balanceDue == 100)
    }

    // Edited down on the Edit screen to what's been paid: it's paid.
    @Test func anInvoiceEditedDownToWhatsPaidIsPaid() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 500)
        Payments.record(300, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        var edits = DocumentEdits(discount: 0, taxRate: 0, dueDate: bill.invoiceDueDate, now: h.clock)
        edits.discountText = "200"
        edits.apply(to: bill, in: h.context)
        #expect(bill.invoiceStatus == .paid)
        #expect(bill.balanceDue == 0)
        #expect(bill.overpaid == 0)
    }

    // Parts recorded on two devices, each short of the total, meet after
    // sync: the sweep marks it paid. A draft (an older PlowR's Reset to
    // Draft keeps its payments) is left alone.
    @Test func theSweepSettlesPartsThatMeetAfterSync() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 500)
        let draft = invoice(h, total: 100, number: "INV-0002")
        draft.invoiceSentAt = nil
        for (amount, target) in [(200.0, bill), (300.0, bill), (100.0, draft)] {
            let payment = Payment(amount: amount, method: "", receivedAt: h.clock, operatorID: "op")
            h.context.insert(payment)
            payment.invoice = target                                              // as an import brings it: not settled
        }
        #expect(bill.invoicePaidAt == nil)
        Payments.settleAll(in: h.context)
        #expect(bill.invoiceStatus == .paid)
        #expect(draft.invoicePaidAt == nil)
    }

    @Test func aReminderAsksForTheBalance() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 500)
        #expect(bill.reminderMessage(locale: Locale(identifier: "en_US")).contains("$500.00"))
        Payments.record(300, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        let message = bill.reminderMessage(locale: Locale(identifier: "en_US"))
        #expect(message.contains("balance of $200.00"))
        #expect(!message.contains("$500.00"))
    }

    // Overpaid (the last part recorded on two devices): received is its
    // payments, the same everywhere, and the sheet says it's overpaid.
    @Test func anOverpaidInvoiceCountsWhatCameIn() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 500)
        Payments.record(300, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        for _ in 0..<2 {
            let payment = Payment(amount: 200, method: "", receivedAt: h.clock, operatorID: "op")
            h.context.insert(payment)
            payment.invoice = bill
        }
        Payments.settle(bill, in: h.context)
        #expect(bill.invoiceStatus == .paid)
        #expect(bill.amountPaid == 700)
        #expect(bill.overpaid == 200)
        #expect(Payments.received([bill]) == 700)
        #expect(Payments.byMonth([bill]).reduce(0) { $0 + $1.received } == 700)
    }

    // Paid on Tuesday, recorded on Friday after the client answered a
    // proposal on Thursday: they stay answered.
    @Test func aLatePaymentDoesntBackdateTheResponse() throws {
        let h = try Harness(stopCount: 0)
        let thursday = h.clock.addingTimeInterval(-86_400)
        h.client.lastMessageSentAt = h.clock.addingTimeInterval(-2 * 86_400)
        h.client.clientRespondedAt = thursday
        let bill = invoice(h, total: 100)
        Payments.record(100, method: "", receivedAt: h.clock.addingTimeInterval(-3 * 86_400), on: bill,
                        in: h.context, now: h.clock)
        #expect(h.client.clientRespondedAt == thursday)
    }

    // Marked paid in full on an older PlowR after a part was recorded here:
    // taking that part back leaves it paid.
    @Test func takingBackAPartOfAnInvoicePaidElsewhereLeavesItPaid() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        let part = try #require(Payments.record(30, method: "", receivedAt: h.clock, on: bill, in: h.context,
                                                now: h.clock))
        bill.invoicePaidAt = h.clock                                              // the older PlowR's Mark Paid
        Payments.delete(part, in: h.context)
        #expect(bill.invoicePaidAt == h.clock)
    }

    // One marked paid before payments were kept, or on an older PlowR: paid in full.
    @Test func anInvoiceMarkedPaidWithoutPaymentsIsPaidInFull() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        bill.invoicePaidAt = h.clock
        #expect(bill.amountPaid == 100)
        #expect(bill.balanceDue == 0)
        Payments.settle(bill, in: h.context)
        #expect(bill.invoicePaidAt == h.clock)                                    // stays paid
        Payments.payInFull(bill, in: h.context, now: h.clock)
        #expect(bill.sortedPayments.isEmpty)
        #expect(Payments.receipts([bill]).map(\.amount) == [100])
    }

    // An older PlowR marked it paid after a part was recorded here.
    @Test func thePartNotRecordedCountsOnTheDayItWasMarkedPaid() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        Payments.record(30, method: "", receivedAt: h.clock.addingTimeInterval(-40 * 86_400), on: bill,
                        in: h.context, now: h.clock)
        bill.invoicePaidAt = h.clock
        #expect(bill.amountPaid == 100)
        #expect(Payments.receipts([bill]).map(\.amount).sorted() == [30, 70])
    }

    @Test func markPaidRecordsTheBalanceByTheClientsUsualMethod() throws {
        let h = try Harness(stopCount: 0)
        h.client.preferredPayment = "zelle"
        let bill = invoice(h, total: 100)
        Payments.record(25, method: "Cash", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        Payments.payInFull(bill, in: h.context, now: h.clock)
        #expect(bill.sortedPayments.map(\.amount) == [25, 75])
        #expect(bill.sortedPayments.last?.method == "Zelle")
        #expect(bill.invoicePaidAt == h.clock)

        let nothingOwed = invoice(h, total: 0, number: "INV-0002")
        Payments.payInFull(nothingOwed, in: h.context, now: h.clock)
        #expect(nothingOwed.invoicePaidAt == h.clock)
        #expect(nothingOwed.sortedPayments.isEmpty)
    }

    @Test func deletingAnInvoiceDeletesItsPayments() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        Payments.record(40, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        try h.context.save()
        h.context.delete(bill)
        try h.context.save()
        #expect(try h.context.fetch(FetchDescriptor<Payment>()).isEmpty)
    }

    // MARK: - Owed and received, the same everywhere

    @Test func owedAndReceivedAddUpBalancesAndPayments() throws {
        let h = try Harness(stopCount: 0)
        let partly = invoice(h, total: 100)
        Payments.record(40, method: "", receivedAt: h.clock, on: partly, in: h.context, now: h.clock)
        let paid = invoice(h, total: 50, number: "INV-0002")
        paid.invoicePaidAt = h.clock
        let owed = invoice(h, total: 25, number: "INV-0003")
        let quote = Proposal(operatorID: "op", client: h.client)
        h.context.insert(quote)
        let documents = [partly, paid, owed, quote]
        #expect(Payments.owed(documents) == 85)                                   // 60 + 25; the quote isn't owed
        #expect(Payments.received(documents) == 90)                               // 40 + 50
        #expect(owed.amountPaid == 0)
    }

    // One payment recorded on two devices before they synced: more than the
    // total. The Dashboard points to it; nothing is removed by itself.
    @Test func anInvoicePaidMoreThanItsTotalIsListed() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        let fine = invoice(h, total: 50, number: "INV-0002")
        Payments.record(100, method: "Cash", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        let twin = Payment(amount: 100, method: "Cash", receivedAt: h.clock, operatorID: "op")
        h.context.insert(twin)
        twin.invoice = bill
        #expect(bill.overpaid == 100)
        #expect(Payments.overpaid([fine, bill]).map(\.id) == [bill.id])
        // A void one isn't listed; the oldest comes first.
        bill.createdAt = h.clock
        let voided = invoice(h, total: 10, number: "INV-0003")
        voided.createdAt = h.clock.addingTimeInterval(-86_400 * 30)
        let extra = Payment(amount: 15, method: "Cash", receivedAt: h.clock, operatorID: "op")
        h.context.insert(extra)
        extra.invoice = voided
        voided.voidedAt = h.clock
        let older = invoice(h, total: 20, number: "INV-0004")
        older.createdAt = h.clock.addingTimeInterval(-86_400 * 10)
        let more = Payment(amount: 25, method: "Cash", receivedAt: h.clock, operatorID: "op")
        h.context.insert(more)
        more.invoice = older
        #expect(Payments.overpaid([fine, bill, voided, older]).map(\.id) == [older.id, bill.id])
        Payments.delete(twin, in: h.context)
        #expect(Payments.overpaid([fine, bill]).isEmpty)
    }

    // Money counts in the month it came: parts of one invoice in two months.
    @Test func moneyByMonthCountsEachPartWhenItCame() throws {
        let h = try Harness(stopCount: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let march = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 10)))
        let april = try #require(calendar.date(from: DateComponents(year: 2027, month: 4, day: 5)))
        let bill = invoice(h, total: 100)
        bill.invoiceSentAt = march
        Payments.record(30, method: "", receivedAt: march, on: bill, in: h.context, now: april)
        Payments.record(20, method: "", receivedAt: april, on: bill, in: h.context, now: april)
        let months = Payments.byMonth([bill], calendar: calendar)
        #expect(months.map(\.received) == [20, 30])                               // April, then March
        #expect(months.map(\.owed) == [0, 50])                                    // owed in the month it went out
    }

    @Test func methodsAreTheUsualOnesThenTheBusinesssOwn() {
        let venmo = PaymentMethod(operatorID: "op", label: "Venmo", value: "@pat", methodType: "link")
        let cash = PaymentMethod(operatorID: "op", label: "cash", value: "", methodType: "cash")
        let off = PaymentMethod(operatorID: "op", label: "PayPal", value: "", methodType: "link")
        off.isActive = false
        #expect(Payments.methods([venmo, cash, off]) == ["Cash", "Check", "Card", "Zelle", "Venmo", "Bank Transfer", "Other"])
        #expect(Payments.method(forPreferred: "check") == "Check")
        #expect(Payments.method(forPreferred: "") == "")
    }

    // MARK: - Where payments show

    @Test func eachPaymentIsOnTheTimelineAndInTheExport() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100, number: "INV-0009")
        Payments.record(30, method: "Check", note: "#12", receivedAt: h.clock.addingTimeInterval(-60), on: bill,
                        in: h.context, now: h.clock)
        Payments.record(70, method: "Cash", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        let events = ClientTimeline.events(for: h.client, now: h.clock, in: h.context)
        let payments = events.filter { if case .payment = $0.kind { true } else { false } }
        #expect(payments.map(\.amount) == [70, 30])
        #expect(payments.last?.detail == "Check · #12")
        let paidEvent = try #require(events.first { $0.kind == .invoicePaid(documentID: bill.id) })
        #expect(paidEvent.amount == nil)                                          // its payments show the money

        let csv = CSVExport.payments([bill], operatorID: "op").components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(csv.count == 3)
        #expect(csv[0].hasSuffix("Received,Invoice,Client,Amount,Method,Note"))              // after the BOM
        #expect(csv[1].contains("INV-0009") && csv[1].contains("30.00") && csv[1].hasSuffix("Check,#12"))
        let invoices = CSVExport.invoices([bill], operatorID: "op")
        #expect(invoices.contains(",100.00,100.00,0.00,"))
    }
}
