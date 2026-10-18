import Foundation
import SwiftData

/// One invoice revised on two devices before they synced (money review,
/// 2026-10-18).
///
/// Each device voids the original and makes its own revision
/// (`ServiceLog.revise`). After syncing, both revisions are live, and the
/// client's balance, Money Owed and the Dashboard count what's owed twice.
/// PlowR doesn't take either back by itself: the other device may have sent
/// its revision or recorded a payment on it by the time it syncs. Each
/// revision's page says so, and so does the Dashboard (`revisedTwice`), so
/// the business deletes or voids one; doing that hands the work to the other
/// (`InvoiceRecords.void`, `ServiceLog.delete`).
///
/// A contract payment's revisions are left to "billed twice"
/// (`ContractInstallments.duplicates`), which already reports them.
enum InvoiceRevisions {
    /// One revision of each original with more than one live revision, the
    /// oldest first: for the Dashboard to point to.
    static func revisedTwice(_ documents: [Proposal], operatorID: String) -> [Proposal] {
        let live = documents.filter { $0.operatorID == operatorID && isLiveRevision($0) && !isContractPayment($0) }
        return Dictionary(grouping: live) { $0.revisionOf }.values
            .filter { $0.count > 1 }
            .compactMap { oldestFirst($0).first }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The other live revision of the original `invoice` revises (`invoice`
    /// itself must be live): the one a banner links to, and the one that takes
    /// over `invoice`'s work when it's voided or deleted.
    static func otherRevision(of invoice: Proposal, among all: [Proposal]) -> Proposal? {
        guard isLiveRevision(invoice) else { return nil }
        return oldestFirst(all.filter {
            $0.id != invoice.id && isLiveRevision($0) && $0.operatorID == invoice.operatorID
                && $0.revisionOf == invoice.revisionOf
        }).first
    }

    /// The same, read from the store: what `InvoiceRecords.void` and
    /// `ServiceLog.delete` hand `invoice`'s work to.
    static func otherRevision(of invoice: Proposal, in context: ModelContext) -> Proposal? {
        guard isLiveRevision(invoice) else { return nil }
        let original = invoice.revisionOf
        let siblings = (try? context.fetch(FetchDescriptor<Proposal>(predicate: #Predicate { $0.revisionOf == original }))) ?? []
        return otherRevision(of: invoice, among: siblings)
    }

    /// Whether `invoice` has another live revision of its original, outside
    /// a contract payment's (that one has its own banner).
    static func hasOtherRevision(_ invoice: Proposal, among all: [Proposal]) -> Bool {
        !isContractPayment(invoice) && otherRevision(of: invoice, among: all) != nil
    }

    /// What the banner on `invoice` says to do about `other`: take back the
    /// one no money came in on, so a client who paid isn't asked again.
    static func advice(for invoice: Proposal, other: Proposal) -> String {
        let lead = "\(other.invoiceNumber) is also a revision of \(invoice.revisionOf): it was revised on two devices before they synced, so what's owed is counted twice."
        switch (hasMoney(invoice), hasMoney(other)) {
        case (true, false):
            return "\(lead) This one has a payment: void the other one."
        case (false, true):
            return "\(lead) The other one has a payment: void this one."
        default:
            return "\(lead) Delete one that wasn't sent (swipe it in Documents), or void one."
        }
    }

    /// The Dashboard's line for a revised-twice invoice.
    static func dashboardDetail(for invoice: Proposal, among all: [Proposal]) -> String {
        let numbers = oldestFirst([invoice] + (otherRevision(of: invoice, among: all).map { [$0] } ?? []))
            .map(\.invoiceNumber).joined(separator: " and ")
        return "\(invoice.clientName) \(invoice.revisionOf): revised on two devices as \(numbers). Void one."
    }

    private static func isLiveRevision(_ invoice: Proposal) -> Bool {
        invoice.isInvoice && !invoice.isDeleted && invoice.voidedAt == nil && !invoice.revisionOf.isEmpty
    }

    private static func isContractPayment(_ invoice: Proposal) -> Bool {
        !invoice.contractID.isEmpty && invoice.installmentIndex > 0
    }

    private static func hasMoney(_ invoice: Proposal) -> Bool {
        invoice.paymentsTotal > Payments.tolerance || invoice.invoicePaidAt != nil
    }

    private static func oldestFirst(_ invoices: [Proposal]) -> [Proposal] {
        invoices.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }
}
