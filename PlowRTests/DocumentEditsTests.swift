//
//  DocumentEditsTests.swift
//  PlowRTests
//

import Testing
import Foundation
import SwiftData
@testable import PlowR

/// What the Edit screen saves. It saves on a swipe down as well as on Done, so
/// opening a sent invoice and closing it must leave the invoice as it was.
@MainActor
struct DocumentEditsTests {

    private let due = Date(timeIntervalSince1970: 1_800_000_000)

    private func invoice(discount: Double, taxRate: Double, dueDate: Date?) throws -> (Proposal, ModelContainer) {
        let container = try ModelContainer(
            for: Proposal.self, ProposalLineItem.self, Client.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let client = Client(name: "Pat Doe", phone: "", address: "", operatorID: "op")
        context.insert(client)
        let doc = Proposal(operatorID: "op", client: client)
        doc.invoiceNumber = "INV-0001"
        doc.discountAmount = discount
        doc.taxRate = taxRate
        doc.invoiceDueDate = dueDate
        let line = ProposalLineItem(serviceName: "Mowing", zoneLabel: "", quantity: 1, unitType: "flat",
                                    unitPrice: 100, sortOrder: 0)
        context.insert(line)
        doc.lineItems = [line]
        context.insert(doc)
        return (doc, container)
    }

    private func edits(for doc: Proposal, now: Date = Date()) -> DocumentEdits {
        DocumentEdits(discount: doc.discountAmount, taxRate: doc.taxRate, dueDate: doc.invoiceDueDate, now: now)
    }

    // An older invoice can hold a discount of 5.125 and a rate of 7.0625. The
    // fields show them rounded, and saving what they show changed the total.
    @Test func openingAndClosingChangesNothing() throws {
        let (doc, container) = try invoice(discount: 5.125, taxRate: 7.0625, dueDate: due)
        _ = container
        let before = doc.total
        let untouched = edits(for: doc)
        #expect(untouched.taxRateText == "7.0625")                   // shown as charged
        #expect(untouched.total(of: doc) == before)
        untouched.apply(to: doc)
        #expect(doc.discountAmount == 5.125)
        #expect(doc.taxRate == 7.0625)
        #expect(doc.invoiceDueDate == due)
        #expect(doc.total == before)
    }

    @Test func aChangedFieldIsSavedAsTyped() throws {
        let (doc, container) = try invoice(discount: 5.125, taxRate: 7.0625, dueDate: due)
        _ = container
        var changed = edits(for: doc)
        changed.discountText = "10"
        changed.taxRateText = "8.875"
        let later = due.addingTimeInterval(7 * 86400)
        changed.dueDate = later
        let shown = changed.total(of: doc)
        changed.apply(to: doc)
        #expect(doc.discountAmount == 10)
        #expect(doc.taxRate == 8.875)
        #expect(doc.invoiceDueDate == later)
        #expect(doc.total == 97.99)                                   // (100 − 10) × 1.08875 = 97.9875
        #expect(InvoiceLines.cents(shown) == InvoiceLines.cents(doc.total))
    }

    @Test func aClearedFieldRemovesTheDiscountOrTax() throws {
        let (doc, container) = try invoice(discount: 5.125, taxRate: 7.0625, dueDate: due)
        _ = container
        var cleared = edits(for: doc)
        cleared.discountText = ""
        cleared.taxRateText = ""
        cleared.apply(to: doc)
        #expect(doc.discountAmount == 0)
        #expect(doc.taxRate == 0)
        #expect(doc.total == 100)
    }

    // An invoice without a due date shows one 30 days out; saving keeps it.
    @Test func anInvoiceWithoutADueDateGetsTheOneShown() throws {
        let (doc, container) = try invoice(discount: 0, taxRate: 0, dueDate: nil)
        _ = container
        edits(for: doc, now: due).apply(to: doc)
        #expect(doc.invoiceDueDate == due.addingTimeInterval(30 * 86400))
    }

    // A proposal gets its due date when it becomes an invoice, not here.
    @Test func aProposalGetsNoDueDate() throws {
        let (doc, container) = try invoice(discount: 0, taxRate: 0, dueDate: nil)
        _ = container
        doc.invoiceNumber = ""
        var changed = edits(for: doc)
        changed.dueDate = due
        changed.apply(to: doc)
        #expect(doc.invoiceDueDate == nil)
    }

    // A value synced from another device while the screen was open survives a
    // field left alone.
    @Test func aFieldLeftAloneDoesNotPutBackAnOldValue() throws {
        let (doc, container) = try invoice(discount: 5, taxRate: 8, dueDate: due)
        _ = container
        let untouched = edits(for: doc)
        let synced = due.addingTimeInterval(86400)
        doc.discountAmount = 7
        doc.taxRate = 6
        doc.invoiceDueDate = synced
        untouched.apply(to: doc)
        #expect(doc.discountAmount == 7)
        #expect(doc.taxRate == 6)
        #expect(doc.invoiceDueDate == synced)
    }
}
