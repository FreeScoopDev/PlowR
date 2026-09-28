//
//  InvoiceNumberingTests.swift
//  PlowRTests
//

import Testing
import Foundation
import SwiftData
@testable import PlowR

/// Invoice numbers must never be handed out twice. The bug these pin: the next
/// number was the count of invoices plus one, so deleting an earlier invoice
/// made the next one repeat a number a live invoice already had.
struct InvoiceNumberingTests {

    @Test func theFirstInvoiceIsOne() {
        #expect(InvoiceNumbering.next(after: []) == "INV-0001")
    }

    // INV-0003 of five deleted: the next is 0006. Counting gave 0005, a duplicate.
    @Test func aDeletedInvoiceNeverCausesADuplicate() {
        #expect(InvoiceNumbering.next(after: ["INV-0001", "INV-0002", "INV-0004", "INV-0005"]) == "INV-0006")
    }

    @Test func revisionsAndOtherTextDoNotMoveTheSequence() {
        #expect(InvoiceNumbering.next(after: ["INV-0007-R1", "INV-0007-R2", "Quote 12", "INV-00x", "INV-"]) == "INV-0001")
        #expect(InvoiceNumbering.next(after: ["INV-0007", "INV-0007-R2"]) == "INV-0008")
    }

    @Test func numbersGrowPastFourDigits() {
        #expect(InvoiceNumbering.next(after: ["INV-9999"]) == "INV-10000")
        #expect(InvoiceNumbering.sequence(of: "INV-10000") == 10_000)
    }

    @Test func aRevisionTakesTheNextFreeSuffix() {
        let used = ["INV-0042", "INV-0042-R1", "INV-0042-R3", "INV-0043-R9"]
        #expect(InvoiceNumbering.nextRevision(of: "INV-0042", used: used) == "INV-0042-R4")
        #expect(InvoiceNumbering.nextRevision(of: "INV-0043", used: used) == "INV-0043-R10")
        #expect(InvoiceNumbering.nextRevision(of: "INV-0044", used: used) == "INV-0044-R1")
    }

    // Revising a revision numbers against the original invoice, not "-R1-R1".
    @Test func revisingARevisionStaysOneLevelDeep() {
        let used = ["INV-0042", "INV-0042-R1"]
        #expect(InvoiceNumbering.nextRevision(of: "INV-0042-R1", used: used) == "INV-0042-R2")
        #expect(InvoiceNumbering.base(of: "INV-0042-R1-R1") == "INV-0042")
    }
}

/// The same rule, reading what's actually saved.
@MainActor
struct InvoiceNumberingStoreTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Proposal.self, ProposalLineItem.self, Client.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @discardableResult
    private func invoice(_ number: String, operatorID: String = "op", in context: ModelContext) -> Proposal {
        let client = Client(name: "Pat", phone: "", address: "", operatorID: operatorID)
        context.insert(client)
        let proposal = Proposal(operatorID: operatorID, client: client)
        proposal.invoiceNumber = number
        context.insert(proposal)
        return proposal
    }

    @Test func onlyThisOperatorsNumbersCount() throws {
        let context = try makeContext()
        invoice("INV-0001", in: context)
        invoice("INV-0002", in: context)
        invoice("INV-0050", operatorID: "someone-else", in: context)
        invoice("", in: context)                                   // a proposal, not an invoice
        #expect(Set(InvoiceNumbering.usedNumbers(operatorID: "op", in: context)) == ["INV-0001", "INV-0002"])
        #expect(InvoiceNumbering.next(operatorID: "op", in: context) == "INV-0003")
    }

    @Test func deletingAnEarlierInvoiceStillGivesAFreshNumber() throws {
        let context = try makeContext()
        invoice("INV-0001", in: context)
        let second = invoice("INV-0002", in: context)
        invoice("INV-0003", in: context)
        try context.save()
        context.delete(second)
        try context.save()
        #expect(InvoiceNumbering.next(operatorID: "op", in: context) == "INV-0004")
    }
}
