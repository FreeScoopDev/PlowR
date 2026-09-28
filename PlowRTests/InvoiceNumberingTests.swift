//
//  InvoiceNumberingTests.swift
//  PlowRTests
//

import Testing
import Foundation
import SwiftData
@testable import PlowR

/// Invoice numbers must not be handed out again while a document still carries
/// them. The bug these pin: the next number was the count of invoices plus one,
/// so deleting an earlier invoice made the next one repeat a live number.
struct InvoiceNumberingTests {

    @Test func theFirstInvoiceIsOne() {
        #expect(InvoiceNumbering.next(after: []) == "INV-0001")
    }

    // INV-0003 of five deleted: the next is 0006. Counting gave 0005, a duplicate.
    @Test func aDeletedInvoiceNeverCausesADuplicate() {
        #expect(InvoiceNumbering.next(after: ["INV-0001", "INV-0002", "INV-0004", "INV-0005"]) == "INV-0006")
    }

    // Revise INV-0007, delete the original: INV-0007-R1 still holds 7, so the
    // next invoice is 0008, not a second "INV-0007" next to INV-0007-R1.
    @Test func aRevisionHoldsItsOriginalsNumber() {
        #expect(InvoiceNumbering.next(after: ["INV-0006", "INV-0007-R1"]) == "INV-0008")
        #expect(InvoiceNumbering.next(after: ["INV-0007-R1", "INV-0007-R2", "INV-0042-R1-R1"]) == "INV-0043")
    }

    @Test func otherTextDoesNotMoveTheSequence() {
        #expect(InvoiceNumbering.next(after: ["Quote 12", "INV-00x", "INV-", "inv-0099"]) == "INV-0001")
    }

    @Test func numbersGrowPastFourDigits() {
        #expect(InvoiceNumbering.next(after: ["INV-9999"]) == "INV-10000")
        #expect(InvoiceNumbering.sequence(of: "INV-10000") == 10_000)
    }

    // A store that can't be read must not restart the sequence at INV-0001.
    @Test func anUnreadableStoreNeverRestartsAtOne() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)          // 2026-09-21 14:13:20 UTC
        let fallback = InvoiceNumbering.next(after: nil, now: now)
        #expect(fallback == "INV-20260921-141320")
        #expect(InvoiceNumbering.sequence(of: fallback) == nil)       // it doesn't disturb the sequence
        #expect(InvoiceNumbering.next(after: ["INV-0003", fallback]) == "INV-0004")
        // A revision made then is still one level deep and still holds its invoice's number.
        let revision = InvoiceNumbering.nextRevision(of: "INV-0003", used: nil, now: now)
        #expect(revision == "INV-0003-R20260921141320")
        #expect(InvoiceNumbering.base(of: revision) == "INV-0003")
        #expect(InvoiceNumbering.next(after: [revision]) == "INV-0004")
    }

    // A number picked for a preview is kept at save unless something took it meanwhile.
    @Test func aPreviewedNumberIsKeptUnlessTaken() {
        let now = Date()
        #expect(InvoiceNumbering.confirmed("INV-0005", used: ["INV-0004"], now: now) == "INV-0005")
        #expect(InvoiceNumbering.confirmed("INV-0005", used: ["INV-0004", "INV-0005"], now: now) == "INV-0006")
        #expect(InvoiceNumbering.confirmed("INV-0005", used: nil, now: now) == "INV-0005")
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
    private func invoice(_ number: String, operatorID: String = "op", in context: ModelContext,
                         insert: Bool = true) -> Proposal {
        let client = Client(name: "Pat", phone: "", address: "", operatorID: operatorID)
        let proposal = Proposal(operatorID: operatorID, client: client)
        proposal.invoiceNumber = number
        if insert {
            context.insert(client)
            context.insert(proposal)
        }
        return proposal
    }

    @Test func onlyThisOperatorsNumbersCount() throws {
        let context = try makeContext()
        invoice("INV-0001", in: context)
        invoice("INV-0002", in: context)
        invoice("INV-0050", operatorID: "someone-else", in: context)
        invoice("", in: context)                                   // a proposal, not an invoice
        #expect(Set(InvoiceNumbering.usedNumbers(operatorID: "op", in: context) ?? []) == ["INV-0001", "INV-0002"])
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

    // The builder's save: an unsaved invoice numbered INV-0005 while a saved one
    // already has INV-0005 (synced from another device) takes INV-0006.
    @Test func aTakenPreviewNumberIsReplacedAtSave() throws {
        let context = try makeContext()
        invoice("INV-0005", in: context)
        try context.save()
        let unsaved = invoice("INV-0005", in: context, insert: false)
        #expect(InvoiceNumbering.confirmed(unsaved.invoiceNumber, operatorID: "op", in: context) == "INV-0006")
        #expect(InvoiceNumbering.confirmed("INV-0009", operatorID: "op", in: context) == "INV-0009")
    }
}
