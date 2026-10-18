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
    /// oldest first: for the Dashboard to point to. `documents` must hold the
    /// originals too: they're how two revisions are known to share one.
    static func revisedTwice(_ documents: [Proposal], operatorID: String) -> [Proposal] {
        let mine = documents.filter { $0.operatorID == operatorID }
        let live = mine.filter { isLiveRevision($0) && !isContractPayment($0) }
        return Dictionary(grouping: live) { "\($0.revisionOf)\u{1F}\($0.clientID)" }.values
            .filter { $0.count > 1 && hasOneOriginal($0[0], among: mine) }
            .compactMap { oldestFirst($0).first }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The other live revision of the same original as `invoice` (`invoice`
    /// itself must be live): the one a banner links to, and the one that takes
    /// over `invoice`'s work when it's voided or deleted. `all` must hold the
    /// original too.
    static func otherRevision(of invoice: Proposal, among all: [Proposal]) -> Proposal? {
        guard isLiveRevision(invoice), hasOneOriginal(invoice, among: all) else { return nil }
        return oldestFirst(all.filter { $0.id != invoice.id && isLiveRevision($0) && isSibling($0, of: invoice) }).first
    }

    /// The same, read from the store: what `InvoiceRecords.void` and
    /// `ServiceLog.delete` hand `invoice`'s work to.
    static func otherRevision(of invoice: Proposal, in context: ModelContext) -> Proposal? {
        guard isLiveRevision(invoice) else { return nil }
        let number = invoice.revisionOf
        let related = (try? context.fetch(FetchDescriptor<Proposal>(predicate: #Predicate {
            $0.revisionOf == number || $0.invoiceNumber == number
        }))) ?? []
        return otherRevision(of: invoice, among: related)
    }

    /// Whether `invoice` has another live revision of its original, outside
    /// a contract payment's (that one has its own banner).
    static func hasOtherRevision(_ invoice: Proposal, among all: [Proposal]) -> Bool {
        !isContractPayment(invoice) && otherRevision(of: invoice, among: all) != nil
    }

    /// Whether taking `invoice` back should hand its work to `other`: never
    /// across two contract payments (`moveBilling` copies the payment over).
    static func canHandOver(_ invoice: Proposal, to other: Proposal) -> Bool {
        invoice.contractID == other.contractID && invoice.installmentIndex == other.installmentIndex
    }

    /// What the banner on `invoice` says to do about `other`: take back the
    /// one no money came in on, so a client who paid isn't asked again.
    static func advice(for invoice: Proposal, other: Proposal) -> String {
        let otherName = invoice.invoiceNumber == other.invoiceNumber
            ? "Another \(other.invoiceNumber), made \(made(other)),"
            : other.invoiceNumber
        let lead = "\(otherName) is also a revision of \(invoice.revisionOf): it was revised on two devices before they synced, so what's owed is counted twice."
        switch (Payments.hasMoneyIn(invoice), Payments.hasMoneyIn(other)) {
        case (true, false):
            return "\(lead) This one has a payment: void the other one."
        case (false, true):
            return "\(lead) The other one has a payment: void this one."
        default:
            return "\(lead) Delete one that wasn't sent (swipe it in Documents), or void one."
        }
    }

    /// What the banner's link says: the other's number, or when it was made
    /// if both have the same number (both sent before syncing).
    static func linkTitle(to other: Proposal, from invoice: Proposal) -> String {
        other.invoiceNumber == invoice.invoiceNumber ? "Open the other copy, made \(made(other))" : "Open \(other.invoiceNumber)"
    }

    /// The Dashboard's line for a revised-twice invoice.
    static func dashboardDetail(for invoice: Proposal, among all: [Proposal]) -> String {
        let pair = oldestFirst([invoice] + (otherRevision(of: invoice, among: all).map { [$0] } ?? []))
        let sameNumber = pair.count == 2 && pair[0].invoiceNumber == pair[1].invoiceNumber
        let names = pair.map { sameNumber ? "\($0.invoiceNumber) (made \(made($0)))" : $0.invoiceNumber }
        return "\(invoice.clientName) \(invoice.revisionOf): revised on two devices as \(names.joined(separator: " and ")). Void one."
    }

    private static func isLiveRevision(_ invoice: Proposal) -> Bool {
        invoice.isInvoice && !invoice.isDeleted && invoice.voidedAt == nil && !invoice.revisionOf.isEmpty
    }

    /// Two revisions of the same original: same business, same client, same
    /// original's number.
    private static func isSibling(_ other: Proposal, of invoice: Proposal) -> Bool {
        other.operatorID == invoice.operatorID && other.clientID == invoice.clientID
            && other.revisionOf == invoice.revisionOf
    }

    /// A revision names its original by number, and two devices can give one
    /// number to two invoices that both went out (never renumbered,
    /// `InvoiceRecords.hasDuplicateNumber`). Then two revisions of that
    /// number may be of two different invoices: not a double, and neither
    /// takes the other's work. Only a number held by one invoice counts.
    private static func hasOneOriginal(_ revision: Proposal, among all: [Proposal]) -> Bool {
        all.filter {
            $0.isInvoice && !$0.isDeleted && $0.operatorID == revision.operatorID
                && $0.invoiceNumber == revision.revisionOf
        }.count <= 1
    }

    private static func isContractPayment(_ invoice: Proposal) -> Bool {
        !invoice.contractID.isEmpty && invoice.installmentIndex > 0
    }

    private static func made(_ invoice: Proposal) -> String {
        invoice.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private static func oldestFirst(_ invoices: [Proposal]) -> [Proposal] {
        invoices.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }
}
