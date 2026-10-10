import Foundation
import SwiftData

/// An invoice is a record once it's out: what may still change, and how it's
/// taken back. Before the pre-launch review (2026-10-10) a sent invoice could
/// be edited under the same number, deleting one deleted its payments, a
/// paid invoice's revision billed the client again, and an invoice number
/// could come round twice.
///
/// - A draft never sent, with no payments, is still a draft: edit it,
///   delete it.
/// - Once sent or paid toward, it's kept: changed by a revision (which takes
///   its payments and voids it), taken back by Void. Never deleted.
/// - Its number is never used again (InvoiceNumbering counts every invoice
///   kept), and a number two devices both gave out is fixed here.
enum InvoiceRecords {
    /// Out of draft: sent, paid toward, paid, or voided.
    static func isIssued(_ document: Proposal) -> Bool {
        guard document.isInvoice else { return false }
        return document.invoiceSentAt != nil || document.invoicePaidAt != nil || document.voidedAt != nil
            || !(document.payments ?? []).isEmpty
    }

    /// Delete is for proposals and drafts that never went out and hold no
    /// money; an issued invoice is voided instead.
    static func canDelete(_ document: Proposal) -> Bool { !isIssued(document) }

    /// Edited in place until it's sent: a draft, or a revision not yet sent
    /// (one of a paid invoice carries its payments, so it's paid until its
    /// lines change; editing settles it). A sent or void invoice is revised.
    static func canEditInPlace(_ document: Proposal) -> Bool {
        !document.isInvoice || (document.invoiceSentAt == nil && document.voidedAt == nil)
    }

    /// Can be voided: an invoice not already void.
    static func canVoid(_ document: Proposal) -> Bool { document.isInvoice && document.voidedAt == nil }

    /// The note a revision leaves on the invoice it replaces.
    static func revisedNote(_ revisionNumber: String) -> String { "Revised as \(revisionNumber)" }

    /// Voids it: kept, owing nothing, its number never reused. What came in
    /// on it stays with it (a "marked paid" with no payment recorded becomes
    /// one, so it still counts as received). A plain void (not a revision's)
    /// gives its work back when no money came in on it: the jobs and visit
    /// billed on it can be billed again, and a contract payment invoiced
    /// again. With money on it, the work stays with it. `releasesWork` is false
    /// only for a revision's original, whose work and money moved with it.
    static func void(_ invoice: Proposal, note: String, now: Date = .now, in context: ModelContext,
                     releasesWork: Bool = true) {
        guard canVoid(invoice) else { return }
        // A revision's original: its payments, implied ones too, already went
        // to the revision (ServiceLog.movePayments).
        if releasesWork { recordImpliedPayment(of: invoice, onto: invoice, in: context) }
        invoice.voidedAt = now
        invoice.voidNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Money came in on it: its work stays billed to it, or billing it
        // again would charge for it twice (Revise moves both together).
        guard releasesWork, invoice.paymentsTotal <= Payments.tolerance else { return }
        ServiceLog.releaseBilling(of: invoice, in: context)
        // The payment is free to invoice again, unless another copy still
        // bills it (made on two devices: ContractInstallments.hasDuplicate).
        if let contract = contract(of: invoice, in: context), !isStillBilled(invoice, in: context) {
            contract.installmentsMade.removeAll { $0 == invoice.installmentIndex }
        }
    }

    private static func isStillBilled(_ invoice: Proposal, in context: ModelContext) -> Bool {
        let id = invoice.contractID
        let theirs = (try? context.fetch(FetchDescriptor<Proposal>(predicate: #Predicate { $0.contractID == id }))) ?? []
        return ContractInstallments.otherInvoice(billing: invoice, among: theirs) != nil
    }

    /// The contract a contract payment's invoice was made for.
    private static func contract(of invoice: Proposal, in context: ModelContext) -> Contract? {
        guard let id = UUID(uuidString: invoice.contractID) else { return nil }
        return (try? context.fetch(FetchDescriptor<Contract>(predicate: #Predicate { $0.id == id })))?.first
    }

    /// Undoes a revision's void when the revision is deleted before it went
    /// out: the original is owed again, as if never revised.
    static func restoreOriginal(of revision: Proposal, in context: ModelContext) {
        guard !revision.revisionOf.isEmpty,
              let original = (try? context.fetch(FetchDescriptor<Proposal>()))?.first(where: {
                  $0.invoiceNumber == revision.revisionOf && $0.operatorID == revision.operatorID
                      && $0.id != revision.id && $0.voidNote == revisedNote(revision.invoiceNumber)
              }) else { return }
        original.voidedAt = nil
        original.voidNote = ""
    }

    /// An invoice marked paid with less recorded than its total (marked paid
    /// before payments were kept, or on an older PlowR): the rest as a
    /// payment on `target`, dated the day it was marked paid, so voiding or
    /// revising never loses money that came in.
    static func recordImpliedPayment(of invoice: Proposal, onto target: Proposal, in context: ModelContext) {
        guard let paidAt = invoice.invoicePaidAt else { return }
        let recorded = InvoiceLines.roundedToCent((invoice.payments ?? []).filter { !$0.isDeleted }
            .reduce(0) { $0 + $1.amount })
        let rest = InvoiceLines.roundedToCent(invoice.total - recorded)
        guard rest > Payments.tolerance else { return }
        let implied = Payment(amount: rest, method: "", receivedAt: paidAt, operatorID: invoice.operatorID)
        implied.clientID = invoice.clientID
        implied.note = "Marked paid on \(invoice.invoiceNumber)"
        context.insert(implied)
        implied.invoice = target
    }

    // MARK: - Numbers given out twice

    /// The same number given out on two devices before iCloud brought them
    /// together. The invoice that went out first keeps it (or, if none went
    /// out, the one made first); every other one not yet sent takes the next
    /// free number (a revision, its next revision number). Two that both
    /// went out are never renumbered, since the client has that number:
    /// `hasDuplicateNumber` lets the invoice's page say so. Run at launch, when
    /// iCloud brings changes and when the app comes back; saves only if
    /// something changed.
    static func resolveDuplicateNumbers(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<Proposal>()) else { return }
        var changed = false
        let groups = Dictionary(grouping: all.filter { $0.isInvoice && !$0.isDeleted }) {
            "\($0.operatorID)\u{1F}\($0.invoiceNumber)"
        }
        for (_, group) in groups where group.count > 1 {
            let keeper = group.sorted { a, b in
                (isIssued(a) ? 0 : 1, a.createdAt, a.id.uuidString) < (isIssued(b) ? 0 : 1, b.createdAt, b.id.uuidString)
            }.first
            for invoice in group where invoice.id != keeper?.id && !isIssued(invoice) {
                invoice.invoiceNumber = invoice.revisionOf.isEmpty
                    ? InvoiceNumbering.next(operatorID: invoice.operatorID, in: context)
                    : InvoiceNumbering.nextRevision(of: invoice.revisionOf, operatorID: invoice.operatorID, in: context)
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Whether another kept invoice of the business has this one's number:
    /// two that both went out before their devices synced.
    /// A void one doesn't count, so revising or voiding one clears it.
    static func hasDuplicateNumber(_ invoice: Proposal, among all: [Proposal]) -> Bool {
        invoice.isInvoice && invoice.voidedAt == nil && all.contains {
            $0.id != invoice.id && !$0.isDeleted && $0.voidedAt == nil && $0.operatorID == invoice.operatorID
                && $0.invoiceNumber == invoice.invoiceNumber
        }
    }
}
