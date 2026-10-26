//
//  ConvertToInvoiceTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Convert to Invoice, from the document's page or the Documents list: one
/// function. The list's own copy only numbered the proposal, so a proposal
/// made into a contract could be invoiced too (billed twice), and a visit's
/// job stayed Not Billed for Bill Unbilled Work to offer again.
@MainActor
struct ConvertToInvoiceTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func proposal(_ h: Harness) -> Proposal {
        let proposal = Proposal(operatorID: "op", client: h.client)
        h.context.insert(proposal)
        return proposal
    }

    @Test func convertingNumbersItDueIn30Days() throws {
        let h = try Harness(stopCount: 0)
        let proposal = proposal(h)
        #expect(InvoiceRecords.convertToInvoice(proposal, now: h.clock, in: h.context))
        #expect(proposal.isInvoice)
        #expect(proposal.invoiceNumber == "INV-0001")
        #expect(proposal.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock))   // the one due-date rule
    }

    // The next number in this business's own sequence: another business's
    // invoices don't count.
    @Test func convertingTakesTheBusinesssNextNumber() throws {
        let h = try Harness(stopCount: 0)
        let earlier = proposal(h)
        earlier.invoiceNumber = "INV-0001"
        let theirs = Proposal(operatorID: "other", client: h.client)
        theirs.invoiceNumber = "INV-0007"
        h.context.insert(theirs)
        let proposal = proposal(h)
        #expect(InvoiceRecords.convertToInvoice(proposal, now: h.clock, in: h.context))
        #expect(proposal.invoiceNumber == "INV-0002")
    }

    // A proposal made for a scheduled visit bills the visit's job: Bill
    // Unbilled Work doesn't offer it again.
    @Test func convertingAVisitsProposalBillsTheVisitsJob() throws {
        let h = try Harness(stopCount: 0)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        let proposal = proposal(h)
        proposal.visitID = visit.id.uuidString
        #expect(ServiceLog.isUnbilled(record, in: h.context))

        #expect(InvoiceRecords.convertToInvoice(proposal, now: h.clock, in: h.context))
        #expect(record.invoiceID == proposal.id.uuidString)
        #expect(!ServiceLog.isUnbilled(record, in: h.context))
    }

    // Made into a contract, it's spoken for: no invoice, nothing changed.
    @Test func aProposalMadeIntoAContractIsNotConverted() throws {
        let h = try Harness(stopCount: 0)
        let proposal = proposal(h)
        let contract = Contract(name: "Season", startDate: h.clock, endDate: h.clock.addingTimeInterval(90 * 86400),
                                operatorID: "op")
        contract.sourceProposalID = proposal.id.uuidString
        h.context.insert(contract)

        #expect(!InvoiceRecords.canConvert(proposal, among: [contract]))
        #expect(!InvoiceRecords.convertToInvoice(proposal, now: h.clock, in: h.context))
        #expect(!proposal.isInvoice)
        #expect(proposal.invoiceDueDate == nil)
    }

    // Another proposal's contract doesn't stop this one.
    @Test func anotherProposalsContractDoesNotBlockIt() throws {
        let h = try Harness(stopCount: 0)
        let other = proposal(h)
        let proposal = proposal(h)
        let contract = Contract(name: "Season", startDate: h.clock, endDate: h.clock, operatorID: "op")
        contract.sourceProposalID = other.id.uuidString
        h.context.insert(contract)
        #expect(InvoiceRecords.canConvert(proposal, among: [contract]))
        #expect(InvoiceRecords.convertToInvoice(proposal, now: h.clock, in: h.context))
    }

    // Converting twice doesn't take a second number.
    @Test func anInvoiceIsNotConvertedAgain() throws {
        let h = try Harness(stopCount: 0)
        let proposal = proposal(h)
        InvoiceRecords.convertToInvoice(proposal, now: h.clock, in: h.context)
        let number = proposal.invoiceNumber
        #expect(!InvoiceRecords.canConvert(proposal, among: []))
        #expect(!InvoiceRecords.convertToInvoice(proposal, now: h.clock.addingTimeInterval(86400), in: h.context))
        #expect(proposal.invoiceNumber == number)
        #expect(proposal.invoiceDueDate == InvoiceTerms.dueDate(from: h.clock))
    }

    // Both screens go through the one function, behind the Pro gate, and
    // neither numbers a proposal itself. Read from the source, as a screen's
    // buttons can't be tapped from a unit test.
    private func source(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PlowR/Views/Proposals/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test(arguments: ["ProposalDetailView.swift", "ProposalListView.swift"])
    func neitherScreenConvertsOnItsOwn(_ file: String) throws {
        let source = try source(file)
        #expect(source.contains("InvoiceRecords.convertToInvoice(proposal, in: modelContext)"))
        #expect(!source.contains("invoiceNumber = InvoiceNumbering.next"))
        #expect(!source.contains("markVisitInvoiced"))
    }

    @Test func theDocumentsListOffersConvertOnlyWithoutAContractBehindTheGate() throws {
        let source = try source("ProposalListView.swift")
        let check = try #require(source.range(of: "if InvoiceRecords.canConvert(proposal, among: allContracts) {"))
        let gated = try #require(source.range(
            of: "$gate.unless(ProGate.edit(access)) { InvoiceRecords.convertToInvoice(proposal, in: modelContext) }"))
        #expect(check.upperBound < gated.lowerBound)
    }

    @Test func theDocumentPageOffersConvertOnlyWithoutAContractBehindTheGate() throws {
        let source = try source("ProposalDetailView.swift")
        let check = try #require(source.range(of: "if let made = Contracts.madeFrom(proposal, among: allContracts) {"))
        let gated = try #require(source.range(of: "$gate.unless(ProGate.edit(access)) { convertToInvoice() }"))
        #expect(check.upperBound < gated.lowerBound)
        #expect(source.contains("guard InvoiceRecords.convertToInvoice(proposal, in: modelContext) else { return }"))
    }
}
