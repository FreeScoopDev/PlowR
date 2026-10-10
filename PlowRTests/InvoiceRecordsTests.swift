//
//  InvoiceRecordsTests.swift
//  PlowRTests
//

import Foundation
import PDFKit
import SwiftData
import Testing
@testable import PlowR

/// An invoice is a record once it's out (pre-launch review, 2026-10-10):
/// revised or voided, never edited in place or deleted; a revision never
/// bills again what was paid; numbers never repeat.
@MainActor
struct InvoiceRecordsTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func invoice(_ h: Harness, total: Double, number: String = "INV-0001", sent: Bool = true,
                         created: Date? = nil) -> Proposal {
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = number
        if sent { invoice.invoiceSentAt = h.clock.addingTimeInterval(-86_400) }
        if let created { invoice.createdAt = created }
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        h.context.insert(item)
        h.context.insert(invoice)
        invoice.lineItems = [item]
        return invoice
    }

    // MARK: Revisions

    @Test func revisingAPaidInvoiceDoesNotBillAgain() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 500, number: "INV-0042")
        Payments.record(500, method: "Check", receivedAt: h.clock, on: original, in: h.context, now: h.clock)
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)

        #expect(revision.balanceDue == 0)                                         // the $500 moved with it
        #expect(revision.paymentsTotal == 500)
        #expect(original.voidedAt != nil && original.voidNote == "Revised as \(revision.invoiceNumber)")
        #expect(original.balanceDue == 0 && original.paymentsTotal == 0)
        // Owed and collected count the $500 once.
        #expect(Payments.owed([original, revision]) == 0)
        #expect(Payments.received([original, revision]) == 500)
    }

    // Marked paid before payments were kept: what it came to moves as a payment.
    @Test func aRevisionOfOneMarkedPaidWithoutPaymentsIsPaidToo() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 300, number: "INV-0007")
        original.invoicePaidAt = h.clock
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        #expect(revision.balanceDue == 0 && revision.paymentsTotal == 300)
        #expect(Payments.received([original, revision]) == 300)
    }

    @Test func aRevisionOfAPartlyPaidInvoiceOwesTheRest() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 200)
        Payments.record(50, method: "", receivedAt: h.clock, on: original, in: h.context, now: h.clock)
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        #expect(revision.balanceDue == 150)
        #expect(Payments.owed([original, revision]) == 150)
    }

    // MARK: Delete, edit, void

    @Test func onlyADraftNeverSentCanBeDeletedOrEditedInPlace() throws {
        let h = try Harness(stopCount: 0)
        let draft = invoice(h, total: 100, sent: false)
        #expect(InvoiceRecords.canDelete(draft) && InvoiceRecords.canEditInPlace(draft))

        let sent = invoice(h, total: 100, number: "INV-0002")
        #expect(!InvoiceRecords.canDelete(sent) && !InvoiceRecords.canEditInPlace(sent))

        let paidToward = invoice(h, total: 100, number: "INV-0003", sent: false)
        Payments.record(10, method: "", receivedAt: h.clock, on: paidToward, in: h.context, now: h.clock)
        #expect(!InvoiceRecords.canDelete(paidToward))

        let proposal = Proposal(operatorID: "op", client: h.client)
        h.context.insert(proposal)
        #expect(InvoiceRecords.canDelete(proposal))
    }

    @Test func aVoidedInvoiceOwesNothingAndKeepsItsPayments() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        Payments.record(40, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        InvoiceRecords.void(bill, note: "Voided", now: h.clock, in: h.context)
        #expect(bill.invoiceStatus == .void && bill.balanceDue == 0)
        #expect(bill.paymentsTotal == 40 && Payments.received([bill]) == 40)    // money that came in stays
        #expect(!InvoiceRecords.canVoid(bill) && !InvoiceRecords.canDelete(bill))
    }

    // MARK: Numbers

    @Test func aVoidedInvoicesNumberIsNeverGivenOutAgain() throws {
        let h = try Harness(stopCount: 0)
        let newest = invoice(h, total: 100, number: "INV-0003")
        _ = invoice(h, total: 100, number: "INV-0002")
        InvoiceRecords.void(newest, note: "Voided", now: h.clock, in: h.context)
        #expect(InvoiceNumbering.next(operatorID: "op", in: h.context) == "INV-0004")
    }

    @Test func aDuplicateDraftNumberFromAnotherDeviceIsRenumbered() throws {
        let h = try Harness(stopCount: 0)
        let first = invoice(h, total: 100, number: "INV-0043", created: h.clock.addingTimeInterval(-60))
        let second = invoice(h, total: 80, number: "INV-0043", sent: false, created: h.clock)
        InvoiceRecords.resolveDuplicateNumbers(in: h.context)
        #expect(first.invoiceNumber == "INV-0043")
        #expect(second.invoiceNumber == "INV-0044")
    }

    @Test func twoSentInvoicesWithOneNumberAreNeverRenumberedButSaidSo() throws {
        let h = try Harness(stopCount: 0)
        let first = invoice(h, total: 100, number: "INV-0043", created: h.clock.addingTimeInterval(-60))
        let second = invoice(h, total: 80, number: "INV-0043", created: h.clock)
        InvoiceRecords.resolveDuplicateNumbers(in: h.context)
        #expect(first.invoiceNumber == "INV-0043" && second.invoiceNumber == "INV-0043")
        #expect(second.notes.isEmpty)                                            // nothing on the client's PDF
        let all = try h.context.fetch(FetchDescriptor<Proposal>())
        #expect(InvoiceRecords.hasDuplicateNumber(second, among: all))
    }

    // An earlier draft and a later sent one: the sent one keeps the number.
    @Test func theSentInvoiceKeepsTheNumberOverAnEarlierDraft() throws {
        let h = try Harness(stopCount: 0)
        let draft = invoice(h, total: 100, number: "INV-0043", sent: false, created: h.clock.addingTimeInterval(-60))
        let sent = invoice(h, total: 80, number: "INV-0043", created: h.clock)
        InvoiceRecords.resolveDuplicateNumbers(in: h.context)
        #expect(sent.invoiceNumber == "INV-0043")
        #expect(draft.invoiceNumber == "INV-0044")
    }

    @Test func aDuplicateRevisionDraftStaysARevision() throws {
        let h = try Harness(stopCount: 0)
        _ = invoice(h, total: 100, number: "INV-0042")
        let a = invoice(h, total: 100, number: "INV-0042-R1", created: h.clock.addingTimeInterval(-60))
        a.revisionOf = "INV-0042"
        let b = invoice(h, total: 90, number: "INV-0042-R1", sent: false, created: h.clock)
        b.revisionOf = "INV-0042"
        InvoiceRecords.resolveDuplicateNumbers(in: h.context)
        #expect(a.invoiceNumber == "INV-0042-R1" && b.invoiceNumber == "INV-0042-R2")
    }

    // MARK: Revisions taken back, voids that give work back

    @Test func deletingAnUnsentRevisionPutsTheOriginalBack() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 300, number: "INV-0042")
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        #expect(original.invoiceStatus == .void)
        #expect(InvoiceRecords.canDelete(revision))
        ServiceLog.delete(revision, in: h.context)
        #expect(original.voidedAt == nil && original.invoiceStatus == .sent)
        #expect(Payments.owed([original]) == 300)
    }

    @Test func aPaidRevisionNotYetSentCanBeEditedAndOwesTheDifference() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 100)
        Payments.record(100, method: "", receivedAt: h.clock, on: original, in: h.context, now: h.clock)
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        #expect(InvoiceRecords.canEditInPlace(revision))
        #expect(!InvoiceRecords.canEditInPlace(original))                        // void
        let more = ProposalLineItem(serviceName: "Salt", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 40)
        h.context.insert(more)
        revision.lineItems = (revision.lineItems ?? []) + [more]
        Payments.settle(revision, in: h.context)
        #expect(revision.balanceDue == 40)
    }

    @Test func voidingOneMarkedPaidKeepsWhatCameIn() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 250)
        bill.invoicePaidAt = h.clock                                              // no Payment recorded
        InvoiceRecords.void(bill, note: "Voided", now: h.clock, in: h.context)
        #expect(Payments.received([bill]) == 250)
        #expect(bill.paymentsTotal == 250)
    }

    @Test func aPlainVoidGivesTheWorkAndContractPaymentBack() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        let record = ServiceRecord(operatorID: "op", sourceKey: "stop:x", source: .route)
        record.invoiceID = bill.id.uuidString
        h.context.insert(record)
        let contract = Contract(name: "Winter", startDate: h.clock, endDate: h.clock.addingTimeInterval(86_400 * 120), operatorID: "op")
        h.context.insert(contract)
        contract.installmentsMade = [2]
        bill.contractID = contract.id.uuidString
        bill.installmentIndex = 2
        InvoiceRecords.void(bill, note: "Voided", now: h.clock, in: h.context)
        #expect(record.invoiceID.isEmpty)
        #expect(contract.installmentsMade.isEmpty)
    }

    // MARK: The PDF

    private func pdfText(_ bill: Proposal) throws -> String {
        let data = PDFGenerator.generate(proposal: bill, profile: nil, forceIsInvoice: true, madeWithPlowR: false)
        let document = try #require(PDFDocument(data: data))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    @Test func aPaidInvoicesPDFSaysPaidNotTotalDue() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        Payments.record(100, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        let text = try pdfText(bill)
        #expect(text.contains("PAID") && !text.contains("TOTAL DUE"))
    }

    @Test func aVoidedInvoicesPDFSaysVoid() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 100)
        InvoiceRecords.void(bill, note: "Revised as INV-0001-R1", now: h.clock, in: h.context)
        let text = try pdfText(bill)
        #expect(text.contains("VOID") && text.contains("Revised as INV-0001-R1") && !text.contains("TOTAL DUE"))
    }
}
