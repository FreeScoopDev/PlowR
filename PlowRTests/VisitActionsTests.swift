//
//  VisitActionsTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The visit sheet's rule book (VisitActions): which actions a visit gets,
/// and why any it could have aren't there.
@MainActor
struct VisitActionsTests {
    private func facts(_ status: VisitStatus = .scheduled, hasClient: Bool = true, active: Bool = true,
                       comped: Bool = false, hasRecord: Bool = false, lines: Bool = false,
                       billing: ServiceLog.BillingStatus? = nil, invoice: String? = nil,
                       canEdit: Bool = true) -> VisitActions.Facts {
        VisitActions.Facts(status: status, hasClient: hasClient, clientName: "Pat Doe", clientIsActive: active,
                           clientIsComped: comped, hasRecord: hasRecord, recordHasLines: lines,
                           recordBilling: billing, invoiceNumber: invoice, canEdit: canEdit)
    }

    @Test func aScheduledVisitCanBeCompletedRecordedAndInvoiced() {
        let plan = VisitActions(facts())
        #expect(plan.actions == [.complete, .recordServices, .completeAndInvoice, .editVisit, .openClient])
        #expect(plan.primary == .complete)
        #expect(plan.reasons.isEmpty)
        #expect(plan.inactiveNote == nil)
        #expect(!plan.needsPro)
    }

    @Test func aScheduledVisitAlreadyBilledShowsItsInvoiceInstead() {
        let plan = VisitActions(facts(invoice: "INV-0007"))
        #expect(plan.actions == [.complete, .recordServices, .viewInvoice, .editVisit, .openClient])
        #expect(plan.title(of: .viewInvoice) == "View Invoice INV-0007")
    }

    @Test func aCompletedVisitWithARecordEditsItsServices() {
        let plan = VisitActions(facts(.completed, hasRecord: true, lines: true, billing: .notBilled))
        #expect(plan.actions == [.editServices, .invoiceWork, .editVisit, .openClient])
        #expect(!plan.actions.contains(.complete))
        #expect(plan.primary == nil)
    }

    @Test func aCompletedVisitWithoutARecordRecordsServices() {
        let plan = VisitActions(facts(.completed))
        #expect(plan.actions == [.recordServices, .editVisit, .openClient])
    }

    @Test func invoiceWorkNeedsUnbilledBillableLines() {
        // No lines.
        let empty = VisitActions(facts(.completed, hasRecord: true, lines: false, billing: .notBilled))
        #expect(!empty.actions.contains(.invoiceWork))
        #expect(empty.reasons == ["No services recorded yet, so there's nothing to bill."])
        // No charge, covered by a contract, from before the log.
        for billing in [ServiceLog.BillingStatus.noCharge, .covered, .notTracked] {
            let plan = VisitActions(facts(.completed, hasRecord: true, lines: true, billing: billing))
            #expect(!plan.actions.contains(.invoiceWork))
            #expect(plan.reasons.count == 1)
        }
    }

    @Test func aCompletedBilledVisitShowsItsInvoice() {
        let plan = VisitActions(facts(.completed, hasRecord: true, lines: true, billing: .invoiced, invoice: "INV-0002"))
        #expect(plan.actions == [.editServices, .viewInvoice, .editVisit, .openClient])
    }

    @Test func skippedAndCancelledVisitsHaveNoFieldActions() {
        for status in [VisitStatus.skipped, .cancelled] {
            let plan = VisitActions(facts(status, hasRecord: true, lines: true, billing: .notBilled))
            #expect(plan.actions == [.editVisit, .openClient])
            #expect(plan.reasons.count == 1)
        }
        let noClient = VisitActions(facts(.skipped, hasClient: false))
        #expect(noClient.actions == [.editVisit])
    }

    @Test func aVisitWithNoClientOnlyCompletes() {
        let plan = VisitActions(facts(hasClient: false))
        #expect(plan.actions == [.complete, .editVisit])
        #expect(plan.reasons == ["No client on file, so there's nothing to record or bill."])
        #expect(plan.primary == .complete)
        let done = VisitActions(facts(.completed, hasClient: false))
        #expect(done.actions == [.editVisit])
    }

    // Recording work done doesn't bring the client back: every action as
    // for an active client, and a note.
    @Test func anInactiveClientsVisitWorksAsUsual() {
        let plan = VisitActions(facts(active: false))
        #expect(plan.actions == VisitActions(facts()).actions)
        #expect(plan.inactiveNote == "Pat Doe is inactive.")
    }

    @Test func aCompedClientsVisitIsNeverInvoiced() {
        let plan = VisitActions(facts(comped: true))
        #expect(plan.actions == [.complete, .recordServices, .editVisit, .openClient])
        #expect(plan.reasons == ["Pat Doe is comped, so their work isn't billed."])
        let done = VisitActions(facts(.completed, comped: true, hasRecord: true, lines: true, billing: .noCharge))
        #expect(!done.actions.contains(.invoiceWork))
        #expect(done.reasons == ["Pat Doe is comped, so their work isn't billed."])
    }

    // Read only: the actions still show, the changes ask ProGate.edit, and
    // viewing is never gated.
    @Test func readOnlyGatesChangesButNotViewing() {
        let plan = VisitActions(facts(invoice: "INV-0001", canEdit: false))
        #expect(plan.actions == [.complete, .recordServices, .viewInvoice, .editVisit, .openClient])
        #expect(plan.needsPro)
        #expect(plan.isGated(.complete))
        #expect(plan.isGated(.recordServices))
        #expect(plan.isGated(.completeAndInvoice))
        #expect(plan.isGated(.invoiceWork))
        #expect(plan.isGated(.editServices))
        #expect(!plan.isGated(.viewInvoice))
        #expect(!plan.isGated(.openClient))
        #expect(!VisitActions(facts()).isGated(.complete))
    }

    // MARK: - Facts from the store

    @Test func billingIsTheVisitsInvoiceThenTheRecords() throws {
        let v = try ServiceLogTests.Visits()
        let visit = v.visit(hoursFromNow: -1)
        // A stale proposalID doesn't count.
        visit.proposalID = UUID().uuidString
        #expect(VisitActions.facts(for: visit, client: v.client, canEdit: true, in: v.context).invoiceNumber == nil)

        let invoice = ServiceLog.newDraftInvoice(for: v.client, items: [], operatorID: "op", now: v.now, in: v.context)
        visit.proposalID = invoice.id.uuidString
        let facts = VisitActions.facts(for: visit, client: v.client, canEdit: true, in: v.context)
        #expect(facts.invoiceNumber == invoice.invoiceNumber)
        #expect(!facts.hasRecord)

        // No visit invoice: the record's.
        let other = v.visit(hoursFromNow: -2)
        let record = try #require(ServiceLog.complete(other, among: try v.all(), in: v.context, now: v.now))
        record.invoiceID = invoice.id.uuidString
        let recordFacts = VisitActions.facts(for: other, client: v.client, canEdit: true, in: v.context)
        #expect(recordFacts.hasRecord)
        #expect(recordFacts.invoiceNumber == invoice.invoiceNumber)
        #expect(recordFacts.recordBilling == .invoiced)
    }
}
