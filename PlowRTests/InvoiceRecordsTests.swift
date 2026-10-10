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
        InvoiceRecords.void(bill, note: "Voided", now: h.clock)
        #expect(bill.invoiceStatus == .void && bill.balanceDue == 0)
        #expect(bill.paymentsTotal == 40 && Payments.received([bill]) == 40)    // money that came in stays
        #expect(!InvoiceRecords.canVoid(bill) && !InvoiceRecords.canDelete(bill))
    }

    // MARK: Numbers

    @Test func aVoidedInvoicesNumberIsNeverGivenOutAgain() throws {
        let h = try Harness(stopCount: 0)
        let newest = invoice(h, total: 100, number: "INV-0003")
        _ = invoice(h, total: 100, number: "INV-0002")
        InvoiceRecords.void(newest, note: "Voided", now: h.clock)
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

    @Test func twoSentInvoicesWithOneNumberAreNotedNeverRenumbered() throws {
        let h = try Harness(stopCount: 0)
        let first = invoice(h, total: 100, number: "INV-0043", created: h.clock.addingTimeInterval(-60))
        let second = invoice(h, total: 80, number: "INV-0043", created: h.clock)
        InvoiceRecords.resolveDuplicateNumbers(in: h.context)
        #expect(first.invoiceNumber == "INV-0043" && second.invoiceNumber == "INV-0043")
        #expect(second.notes.contains(InvoiceRecords.duplicateNote("INV-0043")))
        #expect(first.notes.isEmpty)
        // Run again: noted once.
        InvoiceRecords.resolveDuplicateNumbers(in: h.context)
        #expect(second.notes.components(separatedBy: InvoiceRecords.duplicateNote("INV-0043")).count == 2)
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
        InvoiceRecords.void(bill, note: "Revised as INV-0001-R1", now: h.clock)
        let text = try pdfText(bill)
        #expect(text.contains("VOID") && text.contains("Revised as INV-0001-R1") && !text.contains("TOTAL DUE"))
    }
}
