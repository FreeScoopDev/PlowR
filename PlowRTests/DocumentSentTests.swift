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
        DocumentSent.shared(proposal, toClient: true, in: context, now: now)
        #expect(sam.lastMessageSentAt == now)
        #expect(pat.lastMessageSentAt == nil)
    }

    // Joe's call: a draft invoice shared to someone is sent, due date and all.
    @Test func sharingADraftInvoiceMarksItSent() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        context.insert(invoice)
        DocumentSent.shared(invoice, toClient: true, in: context, now: now)
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
        DocumentSent.shared(invoice, toClient: true, in: context, now: now)
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
        DocumentSent.shared(invoice, toClient: true, in: context, now: now.addingTimeInterval(-86_400))
        DocumentSent.markPaid(invoice, in: context, now: now)
        #expect(pat.clientRespondedAt == now)
    }

    // A proposal shared isn't an invoice sent: no sent date or due date.
    @Test func sharingAProposalLeavesItAProposal() {
        let proposal = Proposal(operatorID: "op", client: pat)
        context.insert(proposal)
        DocumentSent.shared(proposal, toClient: true, in: context, now: now)
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

    // Saved from the builder: an invoice whose number another took while
    // its preview was up is saved with the next number, as a draft (the
    // client has the old number); otherwise the shared invoice is saved sent.
    @Test func aSharedInvoiceRenumberedAtSaveStaysADraft() throws {
        let built = Proposal(operatorID: "op", client: pat)   // built for the preview, not inserted
        built.invoiceNumber = "INV-0012"
        let other = Proposal(operatorID: "op", client: sam)   // synced in meanwhile, with that number
        other.invoiceNumber = "INV-0012"
        context.insert(other)
        DocumentSent.saveBuilt(built, sharedID: built.id, sharedNumber: "INV-0012", in: context, now: now)
        #expect(built.invoiceNumber == "INV-0013")
        #expect(built.invoiceSentAt == nil)
        #expect(built.modelContext != nil)

        let next = Proposal(operatorID: "op", client: pat)
        next.invoiceNumber = "INV-0014"
        DocumentSent.saveBuilt(next, sharedID: next.id, sharedNumber: "INV-0014", in: context, now: now)
        #expect(next.invoiceNumber == "INV-0014")
        #expect(next.invoiceSentAt == now)
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
        DocumentSent.shared(invoice, toClient: true, in: context, now: now)
        #expect(pat.lastMessageSentAt == nil)
    }

    // Joe's call: the share sheet's Mark as Sent switch, off, is for a copy
    // that isn't going to the client (a partner, an accountant, the
    // business's own files). Nothing is marked: a draft invoice stays a
    // draft, a sent one keeps its dates, and no client is awaiting.
    @Test func aCopyThatIsntGoingToTheClientMarksNothing() {
        let draft = Proposal(operatorID: "op", client: pat)
        draft.invoiceNumber = "INV-1001"
        let sent = Proposal(operatorID: "op", client: pat)
        sent.invoiceNumber = "INV-1002"
        let sentAt = now.addingTimeInterval(-5 * 86_400)
        sent.invoiceSentAt = sentAt
        sent.invoiceDueDate = sentAt.addingTimeInterval(30 * 86_400)
        let proposal = Proposal(operatorID: "op", client: sam)
        [draft, sent, proposal].forEach { context.insert($0) }
        for document in [draft, sent, proposal] {
            DocumentSent.shared(document, toClient: false, in: context, now: now)
        }
        #expect(draft.invoiceStatus == .draft)
        #expect(draft.invoiceSentAt == nil && draft.invoiceDueDate == nil)
        #expect(sent.invoiceSentAt == sentAt)
        #expect(sent.invoiceDueDate == sentAt.addingTimeInterval(30 * 86_400))
        #expect(pat.lastMessageSentAt == nil && sam.lastMessageSentAt == nil)
    }

    // What the document's page and a client's document list do when a share
    // sends the PDF: the switch's value decides.
    @Test func aSavedDocumentsShareFollowsTheSwitch() {
        let invoice = Proposal(operatorID: "op", client: pat)
        invoice.invoiceNumber = "INV-1001"
        context.insert(invoice)
        let onSent = DocumentSent.shareHandler(for: invoice, in: context)
        onSent(false)
        #expect(invoice.invoiceStatus == .draft)
        #expect(pat.lastMessageSentAt == nil)
        onSent(true)
        #expect(invoice.invoiceStatus == .sent)
        #expect(pat.lastMessageSentAt != nil)
    }

    // The builder's preview, before the document is saved: shared to the
    // client, they're awaiting now and the builder saves it as shared; an
    // internal copy, neither.
    @Test func thePreviewsShareCountsOnlyWhenGoingToTheClient() {
        #expect(!DocumentSent.sharedBeforeSave(clientID: pat.id.uuidString, toClient: false, in: context, now: now))
        #expect(pat.lastMessageSentAt == nil)
        #expect(DocumentSent.sharedBeforeSave(clientID: pat.id.uuidString, toClient: true, in: context, now: now))
        #expect(pat.lastMessageSentAt == now)
        #expect(sam.lastMessageSentAt == nil)
    }

    // Sharing a paid invoice marks nothing (the share sheet shows no switch
    // for it: screen code, checked on the simulator).
    @Test func sharingCanMarkEverythingButAPaidInvoice() {
        #expect(!DocumentSent.shareCanMark(.paid))
        for status in [InvoiceStatus.proposal, .draft, .sent, .overdue] {
            #expect(DocumentSent.shareCanMark(status), "\(status)")
        }
    }

    // What the switch says, on for each kind of document and off.
    @Test func theSwitchSaysWhatItDoes() {
        #expect(DocumentSent.shareNote(status: .draft, clientName: "Pat Doe", toClient: true)
                == "Sharing it marks the invoice sent and Pat Doe as Awaiting Response")
        #expect(DocumentSent.shareNote(status: .proposal, clientName: "Pat Doe", toClient: true)
                == "Sharing it marks Pat Doe as Awaiting Response")
        #expect(DocumentSent.shareNote(status: .overdue, clientName: "Pat Doe", toClient: true)
                == "Sharing it marks Pat Doe as Awaiting Response")
        #expect(DocumentSent.shareNote(status: .draft, clientName: "Pat Doe", toClient: false)
                == "For a copy that isn't going to Pat Doe: nothing is marked")
        #expect(DocumentSent.shareNote(status: .proposal, clientName: "", toClient: true)
                == "Sharing it marks the client as Awaiting Response")
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
