import Foundation
import SwiftData
import Testing
@testable import PlowR

/// One invoice revised on two devices before they synced: both revisions are
/// live and what's owed counts twice. PlowR points to them (Dashboard, each
/// revision's page) and never takes one back by itself; taking one back hands
/// its work to the other.
@MainActor
struct InvoiceRevisionsTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func invoice(_ h: Harness, total: Double, number: String) -> Proposal {
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = number
        invoice.invoiceSentAt = h.clock.addingTimeInterval(-86_400)
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        h.context.insert(item)
        h.context.insert(invoice)
        invoice.lineItems = [item]
        return invoice
    }

    /// What two devices leave after syncing: each revised the original (the
    /// second `revise` stands in for the other device's), and the second
    /// revision was renumbered (`resolveDuplicateNumbers`).
    private func revisedOnTwoDevices(_ h: Harness, total: Double = 300)
        throws -> (original: Proposal, first: Proposal, second: Proposal) {
        let original = invoice(h, total: total, number: "INV-0042")
        let first = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        let second = ServiceLog.revise(original, client: h.client, now: h.clock.addingTimeInterval(60), in: h.context)
        second.createdAt = first.createdAt.addingTimeInterval(60)
        try h.context.save()
        return (original, first, second)
    }

    private func all(_ h: Harness) throws -> [Proposal] { try h.context.fetch(FetchDescriptor<Proposal>()) }

    // MARK: Finding them

    @Test func twoLiveRevisionsOfOneInvoiceAreFound() throws {
        let h = try Harness(stopCount: 0)
        let (original, first, second) = try revisedOnTwoDevices(h)
        #expect(first.revisionOf == "INV-0042" && second.revisionOf == "INV-0042")
        #expect(first.invoiceNumber != second.invoiceNumber)
        let documents = try all(h)
        // Owed twice: the reason for the warning.
        #expect(Payments.owed(documents) == 600)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").map(\.id) == [first.id])
        #expect(InvoiceRevisions.otherRevision(of: first, among: documents)?.id == second.id)
        #expect(InvoiceRevisions.otherRevision(of: second, among: documents)?.id == first.id)
        #expect(InvoiceRevisions.hasOtherRevision(first, among: documents))
        #expect(InvoiceRevisions.otherRevision(of: original, among: documents) == nil)   // void, not a revision
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "someone else").isEmpty)
    }

    /// Revising a revision makes a chain, one live at a time: not a double.
    @Test func aChainOfRevisionsIsNotRevisedTwice() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 300, number: "INV-0050")
        let first = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        let second = ServiceLog.revise(first, client: h.client, now: h.clock, in: h.context)
        let documents = try all(h)
        #expect(second.revisionOf == first.invoiceNumber)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(!InvoiceRevisions.hasOtherRevision(second, among: documents))
        #expect(Payments.owed(documents) == 300)
    }

    @Test func oneOfEachOriginalOldestFirst() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let other = invoice(h, total: 80, number: "INV-0060")
        let a = ServiceLog.revise(other, client: h.client, now: h.clock, in: h.context)
        let b = ServiceLog.revise(other, client: h.client, now: h.clock, in: h.context)
        a.createdAt = first.createdAt.addingTimeInterval(-3_600)
        b.createdAt = second.createdAt.addingTimeInterval(3_600)
        let found = InvoiceRevisions.revisedTwice(try all(h), operatorID: "op")
        #expect(found.map(\.id) == [a.id, first.id])
    }

    /// Billed twice already reports a contract payment's two invoices.
    @Test func aContractPaymentIsLeftToBilledTwice() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        for revision in [first, second] {
            revision.contractID = UUID().uuidString
            revision.installmentIndex = 1
        }
        second.contractID = first.contractID
        let documents = try all(h)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(!InvoiceRevisions.hasOtherRevision(first, among: documents))
        #expect(ContractInstallments.duplicates(documents, operatorID: "op").map(\.id) == [first.id])
    }

    // MARK: What it says

    @Test func theDashboardNamesBothRevisions() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let detail = InvoiceRevisions.dashboardDetail(for: first, among: try all(h))
        #expect(detail == "\(h.client.name) INV-0042: revised on two devices as \(first.invoiceNumber) and \(second.invoiceNumber). Void one.")
    }

    @Test func theBannerSaysWhichToTakeBack() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        #expect(InvoiceRevisions.advice(for: first, other: second).hasSuffix("Delete one that wasn't sent (swipe it in Documents), or void one."))
        #expect(InvoiceRevisions.advice(for: first, other: second).hasPrefix("\(second.invoiceNumber) is also a revision of INV-0042"))
        Payments.record(100, method: "Check", receivedAt: h.clock, on: second, in: h.context, now: h.clock)
        #expect(InvoiceRevisions.advice(for: first, other: second).hasSuffix("The other one has a payment: void this one."))
        #expect(InvoiceRevisions.advice(for: second, other: first).hasSuffix("This one has a payment: void the other one."))
    }

    // MARK: Taking one back

    /// Voiding one: the warning goes, what's owed counts once, and its work
    /// goes to the other revision instead of back to billable.
    @Test func voidingOneHandsItsWorkToTheOther() throws {
        let h = try Harness(stopCount: 1)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        // The second device's move won when they synced.
        record.invoiceID = second.id.uuidString
        visit.proposalID = second.id.uuidString

        InvoiceRecords.void(second, note: "Revised twice", now: h.clock, in: h.context)
        try h.context.save()
        let documents = try all(h)
        #expect(record.invoiceID == first.id.uuidString)
        #expect(visit.proposalID == first.id.uuidString)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(!InvoiceRevisions.hasOtherRevision(first, among: documents))
        #expect(Payments.owed(documents) == 300)
    }

    /// A plain void of the only live revision still frees its work.
    @Test func voidingTheLastRevisionStillReleasesItsWork() throws {
        let h = try Harness(stopCount: 1)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        record.invoiceID = first.id.uuidString
        InvoiceRecords.void(second, note: "Revised twice", now: h.clock, in: h.context)
        InvoiceRecords.void(first, note: "Wrong client", now: h.clock, in: h.context)
        #expect(record.invoiceID.isEmpty)
    }

    /// Deleting the unsent one whose number the original's void note names:
    /// the original stays void (it used to come back, owed beside the other
    /// revision), and the work goes to the other revision.
    @Test func deletingOneKeepsTheOriginalVoid() throws {
        let h = try Harness(stopCount: 1)
        let (original, first, second) = try revisedOnTwoDevices(h)
        // After syncing, the original's note names the first device's revision.
        original.voidNote = InvoiceRecords.revisedNote(first.invoiceNumber)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        record.invoiceID = first.id.uuidString
        visit.proposalID = first.id.uuidString
        #expect(InvoiceRecords.canDelete(first))

        ServiceLog.delete(first, in: h.context)
        try h.context.save()
        let documents = try all(h)
        #expect(original.voidedAt != nil)
        #expect(record.invoiceID == second.id.uuidString)
        #expect(visit.proposalID == second.id.uuidString)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(Payments.owed(documents) == 300)
    }

    /// Deleting a lone revision still gives the original back, as before.
    @Test func deletingALoneRevisionStillRestoresTheOriginal() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 300, number: "INV-0070")
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        ServiceLog.delete(revision, in: h.context)
        try h.context.save()
        #expect(original.voidedAt == nil)
        #expect(Payments.owed(try all(h)) == 300)
    }

    // MARK: Not a double

    /// Two invoices sent with one number from two devices (never
    /// renumbered), each revised for its own reason: two real invoices, not
    /// one revised twice. Taking one back mustn't touch the other.
    @Test func revisionsOfTwoInvoicesSharingANumberAreNotADouble() throws {
        let h = try Harness(stopCount: 1)
        let other = Client(name: "Other Client", phone: "", address: "9 Elm St", operatorID: "op")
        h.context.insert(other)
        let mine = invoice(h, total: 300, number: "INV-0042")
        let theirs = invoice(h, total: 120, number: "INV-0042")
        theirs.clientID = other.id.uuidString
        theirs.clientName = other.name
        let myRevision = ServiceLog.revise(mine, client: h.client, now: h.clock, in: h.context)
        let theirRevision = ServiceLog.revise(theirs, client: other, now: h.clock, in: h.context)
        let visit = ScheduledVisit(operatorID: "op", clientID: other.id.uuidString, clientName: other.name,
                                   clientAddress: other.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        record.invoiceID = theirRevision.id.uuidString
        let documents = try all(h)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(!InvoiceRevisions.hasOtherRevision(myRevision, among: documents))
        #expect(!InvoiceRevisions.hasOtherRevision(theirRevision, among: documents))

        // Taking theirs back gives their own original back, with its work.
        ServiceLog.delete(theirRevision, in: h.context)
        try h.context.save()
        #expect(theirs.voidedAt == nil)
        #expect(mine.voidedAt != nil)
        #expect(record.invoiceID == theirs.id.uuidString)
        #expect(myRevision.voidedAt == nil)
    }

    /// The same, for one client with two invoices sharing a number: which
    /// revision is of which can't be told, so neither is called a double.
    @Test func oneClientsTwoInvoicesSharingANumberAreNotADouble() throws {
        let h = try Harness(stopCount: 0)
        let first = invoice(h, total: 300, number: "INV-0042")
        let second = invoice(h, total: 120, number: "INV-0042")
        let a = ServiceLog.revise(first, client: h.client, now: h.clock, in: h.context)
        let b = ServiceLog.revise(second, client: h.client, now: h.clock, in: h.context)
        let documents = try all(h)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(InvoiceRevisions.otherRevision(of: a, among: documents) == nil)
        #expect(InvoiceRevisions.otherRevision(of: b, in: h.context) == nil)
    }

    /// Another business's revision of the same number is never the other one.
    @Test func anotherBusinessesRevisionIsIgnored() throws {
        let h = try Harness(stopCount: 0)
        let original = invoice(h, total: 300, number: "INV-0042")
        let mine = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        let stranger = Proposal(operatorID: "someone else", client: h.client)
        stranger.invoiceNumber = "INV-0042-R1"
        stranger.revisionOf = "INV-0042"
        h.context.insert(stranger)
        let documents = try all(h)
        #expect(InvoiceRevisions.otherRevision(of: mine, among: documents) == nil)
        #expect(InvoiceRevisions.otherRevision(of: mine, in: h.context) == nil)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
    }

    /// Deleted but not yet saved: no longer counts.
    @Test func aDeletedRevisionDoesntCount() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let documents = try all(h)
        h.context.delete(second)
        #expect(second.isDeleted)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(InvoiceRevisions.otherRevision(of: first, among: documents) == nil)
    }

    /// Both sent before syncing, so both kept the same number: told apart by
    /// when each was made.
    @Test func twoRevisionsWithOneNumberAreToldApart() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        second.invoiceNumber = first.invoiceNumber
        let documents = try all(h)
        let detail = InvoiceRevisions.dashboardDetail(for: first, among: documents)
        #expect(detail.contains("\(first.invoiceNumber) (made "))
        #expect(detail.components(separatedBy: "(made ").count == 3)
        #expect(InvoiceRevisions.linkTitle(to: second, from: first).hasPrefix("Open the other copy, made "))
        #expect(InvoiceRevisions.advice(for: first, other: second).hasPrefix("Another \(first.invoiceNumber), made "))
    }

    /// Renumbered when they synced, so no void note names the revision: its
    /// own client's original still takes its work back, never another's.
    @Test func aRenumberedRevisionGoesBackToItsOwnClientsOriginal() throws {
        let h = try Harness(stopCount: 1)
        let other = Client(name: "Other Client", phone: "", address: "9 Elm St", operatorID: "op")
        h.context.insert(other)
        // Theirs first, so it's what an unordered look finds first.
        let theirs = invoice(h, total: 120, number: "INV-0042")
        theirs.clientID = other.id.uuidString
        let mine = invoice(h, total: 300, number: "INV-0042")
        let myRevision = ServiceLog.revise(mine, client: h.client, now: h.clock, in: h.context)
        myRevision.invoiceNumber = "INV-0042-R7"
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        record.invoiceID = myRevision.id.uuidString
        ServiceLog.delete(myRevision, in: h.context)
        #expect(record.invoiceID == mine.id.uuidString)
    }

    /// Two copies of different contract payments are never handed each
    /// other's work: voiding one releases it as a plain void would.
    @Test func noHandOverBetweenDifferentContractPayments() throws {
        let h = try Harness(stopCount: 1)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let contract = UUID().uuidString
        first.contractID = contract
        first.installmentIndex = 1
        second.contractID = contract
        second.installmentIndex = 2
        #expect(!InvoiceRevisions.canHandOver(second, to: first))
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        record.invoiceID = second.id.uuidString
        InvoiceRecords.void(second, note: "Wrong payment", now: h.clock, in: h.context)
        #expect(record.invoiceID.isEmpty)
        #expect(first.installmentIndex == 1)
    }

    // MARK: More that isn't a double (test audit)

    /// One client's revisions of two different invoices aren't each other's.
    @Test func revisionsOfTwoDifferentInvoicesArentADouble() throws {
        let h = try Harness(stopCount: 0)
        let a = ServiceLog.revise(invoice(h, total: 300, number: "INV-0042"), client: h.client, now: h.clock, in: h.context)
        let b = ServiceLog.revise(invoice(h, total: 80, number: "INV-0060"), client: h.client, now: h.clock, in: h.context)
        let documents = try all(h)
        #expect(!InvoiceRevisions.hasOtherRevision(a, among: documents))
        #expect(InvoiceRevisions.otherRevision(of: b, among: documents) == nil)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
    }

    /// Two plain invoices, no revisions: nothing to report.
    @Test func twoPlainInvoicesArentRevisions() throws {
        let h = try Harness(stopCount: 0)
        let a = invoice(h, total: 300, number: "INV-0042")
        _ = invoice(h, total: 80, number: "INV-0043")
        let documents = try all(h)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").isEmpty)
        #expect(!InvoiceRevisions.hasOtherRevision(a, among: documents))
    }

    /// Delete, like void, never hands work across two contract payments.
    @Test func deleteDoesntHandOverBetweenDifferentContractPayments() throws {
        let h = try Harness(stopCount: 1)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let contract = UUID().uuidString
        first.contractID = contract
        first.installmentIndex = 1
        second.contractID = contract
        second.installmentIndex = 2
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        record.invoiceID = second.id.uuidString
        ServiceLog.delete(second, in: h.context)
        #expect(record.invoiceID != first.id.uuidString)
    }

    /// Another business's invoice with the original's number doesn't hide
    /// a real double.
    @Test func anotherBusinessesNumberDoesntHideADouble() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        let stranger = Proposal(operatorID: "someone else", client: h.client)
        stranger.invoiceNumber = "INV-0042"
        h.context.insert(stranger)
        let documents = try all(h)
        #expect(InvoiceRevisions.otherRevision(of: first, among: documents)?.id == second.id)
        #expect(InvoiceRevisions.revisedTwice(documents, operatorID: "op").map(\.id) == [first.id])
    }

    /// One client, two invoices sharing a number, each revised: deleting one
    /// revision gives its work to the original whose void names it.
    @Test func deleteGoesBackToTheOriginalItRevised() throws {
        let h = try Harness(stopCount: 1)
        let firstOriginal = invoice(h, total: 300, number: "INV-0042")
        let secondOriginal = invoice(h, total: 120, number: "INV-0042")
        _ = ServiceLog.revise(firstOriginal, client: h.client, now: h.clock, in: h.context)
        let revision = ServiceLog.revise(secondOriginal, client: h.client, now: h.clock, in: h.context)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let record = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        record.invoiceID = revision.id.uuidString
        ServiceLog.delete(revision, in: h.context)
        #expect(record.invoiceID == secondOriginal.id.uuidString)
        #expect(secondOriginal.voidedAt == nil && firstOriginal.voidedAt != nil)
    }

    /// Marked paid with no payment recorded counts as money in.
    @Test func markedPaidCountsAsAPayment() throws {
        let h = try Harness(stopCount: 0)
        let (_, first, second) = try revisedOnTwoDevices(h)
        second.invoicePaidAt = h.clock
        #expect(InvoiceRevisions.advice(for: first, other: second).hasSuffix("The other one has a payment: void this one."))
    }
}

