//
//  DocumentSentTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// "Awaiting Response" on a client's page follows invoices and proposals
/// marked sent. A text from the client's page used to set it, and marking a
/// document sent didn't.
@MainActor
struct DocumentSentTests {
    let context: ModelContext
    let pat: Client
    let sam: Client

    init() throws {
        let container = try ModelContainer(
            for: Client.self, Proposal.self, ProposalLineItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = container.mainContext
        pat = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
        sam = Client(name: "Sam Roe", phone: "555-0200", address: "2 Elm St", operatorID: "op")
        context.insert(pat)
        context.insert(sam)
    }

    @Test func aDocumentSentMakesItsClientAwaitAResponse() {
        let when = Date(timeIntervalSinceReferenceDate: 812_000_000)
        pat.clientRespondedAt = when.addingTimeInterval(-86_400)      // answered an earlier one
        let invoice = Proposal(operatorID: "op", client: pat)
        context.insert(invoice)
        DocumentSent.awaitResponse(to: invoice, in: context, now: when)
        #expect(pat.lastMessageSentAt == when)
        #expect(pat.clientRespondedAt == nil)
        #expect(sam.lastMessageSentAt == nil)
    }

    @Test func aDocumentWhoseClientIsGoneChangesNothing() {
        let orphan = Proposal(operatorID: "op", client: pat)
        orphan.clientID = UUID().uuidString
        context.insert(orphan)
        DocumentSent.awaitResponse(to: orphan, in: context)
        #expect(pat.lastMessageSentAt == nil)
        #expect(sam.lastMessageSentAt == nil)
    }
}
