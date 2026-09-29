//
//  DocumentSentTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import PlowR

/// "Awaiting Response" on a client's page follows invoices and proposals
/// sent. A text from the client's page used to set it, and sending a
/// document didn't.
@MainActor
struct DocumentSentTests {
    /// Kept: a container that goes away resets its context, and every model
    /// in it is destroyed.
    let container: ModelContainer
    let context: ModelContext
    let pat: Client
    let sam: Client
    let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    init() throws {
        container = try ModelContainer(
            for: Client.self, Proposal.self, ProposalLineItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = container.mainContext
        pat = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
        sam = Client(name: "Sam Roe", phone: "555-0200", address: "2 Elm St", operatorID: "op")
        context.insert(pat)
        context.insert(sam)
    }

    // Mark Sent, from any of its four places: sent now, due in 30 days, and
    // the client awaiting a response.
    @Test func markingAnInvoiceSentMakesItsClientAwaitAResponse() {
        pat.clientRespondedAt = now.addingTimeInterval(-86_400)       // answered an earlier one
        let invoice = Proposal(operatorID: "op", client: pat)
        context.insert(invoice)
        DocumentSent.markSent(invoice, in: context, now: now)
        #expect(invoice.invoiceSentAt == now)
        #expect(invoice.invoiceDueDate == now.addingTimeInterval(30 * 86_400))
        #expect(pat.lastMessageSentAt == now)
        #expect(pat.clientRespondedAt == nil)
        #expect(sam.lastMessageSentAt == nil)
    }

    @Test func aDueDateAlreadySetIsKept() {
        let invoice = Proposal(operatorID: "op", client: pat)
        let due = now.addingTimeInterval(7 * 86_400)
        invoice.invoiceDueDate = due
        context.insert(invoice)
        DocumentSent.markSent(invoice, in: context, now: now)
        #expect(invoice.invoiceDueDate == due)
    }

    // A proposal (or invoice) shared to someone from the share sheet.
    @Test func aDocumentSharedToSomeoneMakesItsClientAwait() {
        let proposal = Proposal(operatorID: "op", client: sam)
        context.insert(proposal)
        DocumentSent.shared(proposal, in: context, now: now)
        #expect(sam.lastMessageSentAt == now)
        #expect(pat.lastMessageSentAt == nil)
    }

    // Joe's call: a draft invoice shared to someone is sent, due date and all.
    @Test func sharingADraftInvoiceMarksItSent() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        context.insert(invoice)
        DocumentSent.shared(invoice, in: context, now: now)
        #expect(invoice.invoiceSentAt == now)
        #expect(invoice.invoiceDueDate == now.addingTimeInterval(30 * 86_400))
        #expect(pat.lastMessageSentAt == now)
    }

    @Test func sharingASentInvoiceAgainKeepsItsDates() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        let sent = now.addingTimeInterval(-5 * 86_400)
        invoice.invoiceSentAt = sent
        invoice.invoiceDueDate = sent.addingTimeInterval(30 * 86_400)
        context.insert(invoice)
        DocumentSent.shared(invoice, in: context, now: now)
        #expect(invoice.invoiceSentAt == sent)
        #expect(invoice.invoiceDueDate == sent.addingTimeInterval(30 * 86_400))
        #expect(pat.lastMessageSentAt == now)
    }

    // A payment is the client's response to the invoice they were awaiting on.
    @Test func payingTheInvoiceTheyWereAwaitingEndsIt() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        context.insert(invoice)
        let sent = now.addingTimeInterval(-2 * 86_400)
        DocumentSent.markSent(invoice, in: context, now: sent)
        DocumentSent.markPaid(invoice, in: context, now: now)
        #expect(invoice.invoicePaidAt == now)
        #expect(pat.clientRespondedAt == now)
    }

    // The usual way out: Mark Sent, then the PDF shared, then paid.
    @Test func payingAfterMarkSentAndShareEndsIt() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        context.insert(invoice)
        DocumentSent.markSent(invoice, in: context, now: now.addingTimeInterval(-5 * 86_400))
        DocumentSent.shared(invoice, in: context, now: now.addingTimeInterval(-86_400))
        DocumentSent.markPaid(invoice, in: context, now: now)
        #expect(pat.clientRespondedAt == now)
    }

    // A proposal shared isn't an invoice sent: no sent date or due date.
    @Test func sharingAProposalLeavesItAProposal() {
        let proposal = Proposal(operatorID: "op", client: pat)
        context.insert(proposal)
        DocumentSent.shared(proposal, in: context, now: now)
        #expect(proposal.invoiceSentAt == nil)
        #expect(proposal.invoiceDueDate == nil)
        #expect(pat.lastMessageSentAt == now)
    }

    // The builder saves a document as shared only if it's the one its
    // preview shared, with the number the client saw.
    @Test func onlyTheDocumentThePreviewSharedIsSavedAsShared() {
        let shared = Proposal(operatorID: "op", client: pat)
        shared.invoiceNumber = "INV-0012"
        #expect(DocumentSent.wasSharedBeforeSave(shared, sharedID: shared.id, sharedNumber: "INV-0012"))
        let rebuilt = Proposal(operatorID: "op", client: pat)   // Back, edits, Save Draft
        rebuilt.invoiceNumber = "INV-0012"
        #expect(!DocumentSent.wasSharedBeforeSave(rebuilt, sharedID: shared.id, sharedNumber: "INV-0012"))
        shared.invoiceNumber = "INV-0013"                      // renumbered at save
        #expect(!DocumentSent.wasSharedBeforeSave(shared, sharedID: shared.id, sharedNumber: "INV-0012"))
        #expect(!DocumentSent.wasSharedBeforeSave(shared, sharedID: nil, sharedNumber: ""))
    }

    @Test func payingWithNothingAwaitedChangesOnlyTheInvoice() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        invoice.invoiceSentAt = now.addingTimeInterval(-86_400)
        context.insert(invoice)
        DocumentSent.markPaid(invoice, in: context, now: now)
        #expect(invoice.invoicePaidAt == now)
        #expect(pat.clientRespondedAt == nil)
        #expect(pat.lastMessageSentAt == nil)
    }

    // A paid invoice shared is a receipt: nothing is owed or awaited.
    @Test func aPaidInvoiceSharedAwaitsNothing() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        invoice.invoiceSentAt = now.addingTimeInterval(-86_400)
        invoice.invoicePaidAt = now
        context.insert(invoice)
        DocumentSent.shared(invoice, in: context, now: now)
        #expect(pat.lastMessageSentAt == nil)
    }

    @Test func onlyAShareThatSendsCounts() {
        #expect(DocumentSent.isSend(.message))
        #expect(DocumentSent.isSend(.mail))
        #expect(DocumentSent.isSend(.airDrop))
        #expect(DocumentSent.isSend(UIActivity.ActivityType("net.whatsapp.WhatsApp.ShareExtension")))
        #expect(!DocumentSent.isSend(nil))
        #expect(!DocumentSent.isSend(.copyToPasteboard))
        #expect(!DocumentSent.isSend(.print))
        #expect(!DocumentSent.isSend(.saveToCameraRoll))
        #expect(!DocumentSent.isSend(UIActivity.ActivityType("com.apple.DocumentManagerUICore.SaveToFiles")))
        #expect(!DocumentSent.isSend(.openInIBooks))
        // Seen on the iOS 26.5 simulator, opening the PDF in the Preview app.
        #expect(!DocumentSent.isSend(UIActivity.ActivityType("com.apple.UIKit.activity.RemoteOpenInApplication-ByCopy")))
        #expect(!DocumentSent.isSend(UIActivity.ActivityType("com.apple.mobilenotes.SharingExtension")))
        #expect(!DocumentSent.isSend(UIActivity.ActivityType("com.getdropbox.Dropbox.ActionExtension")))
    }

    @Test func aDocumentWhoseClientIsGoneChangesNothing() {
        DocumentSent.awaitResponse(clientID: UUID().uuidString, in: context, now: now)
        #expect(pat.lastMessageSentAt == nil)
        #expect(sam.lastMessageSentAt == nil)
    }

    // Stamps set by texts before this version would read as a document sent:
    // cleared once, and only once.
    @Test func textStampsAreClearedOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "DocumentSentTests-\(UUID().uuidString)"))
        pat.lastMessageSentAt = now
        sam.clientRespondedAt = now
        DocumentSent.clearTextStamps(in: context, defaults: defaults)
        #expect(pat.lastMessageSentAt == nil)
        #expect(sam.clientRespondedAt == nil)
        let invoice = Proposal(operatorID: "op", client: pat)
        context.insert(invoice)
        DocumentSent.markSent(invoice, in: context, now: now)
        DocumentSent.awaitResponse(clientID: sam.id.uuidString, in: context, now: now)   // a proposal shared since
        DocumentSent.clearTextStamps(in: context, defaults: defaults)
        #expect(pat.lastMessageSentAt == now)
        #expect(sam.lastMessageSentAt == now)                 // no invoice explains it: kept because it's once
    }

    // A second device updated later: an invoice marked sent on the first,
    // since its update, isn't cleared with the old text marks.
    @Test func aStampAnInvoiceExplainsIsKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "DocumentSentTests-\(UUID().uuidString)"))
        let invoice = Proposal(operatorID: "op", client: pat)
        context.insert(invoice)
        DocumentSent.markSent(invoice, in: context, now: now)
        // Sam's mark is from the same moment as Pat's invoice, and Sam has an
        // invoice sent at another time: neither explains it.
        let samsInvoice = Proposal(operatorID: "op", client: sam)
        samsInvoice.invoiceSentAt = now.addingTimeInterval(-3_600)
        context.insert(samsInvoice)
        sam.lastMessageSentAt = now
        DocumentSent.clearTextStamps(in: context, defaults: defaults)
        #expect(pat.lastMessageSentAt == now)
        #expect(sam.lastMessageSentAt == nil)
    }
}
