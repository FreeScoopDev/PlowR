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

    /// Delete is for proposals and drafts that never went out; an issued
    /// invoice is voided instead.
    static func canDelete(_ document: Proposal) -> Bool { !isIssued(document) }

    /// Edited in place only as a draft; an issued invoice is revised.
    static func canEditInPlace(_ document: Proposal) -> Bool { !isIssued(document) }

    /// Can be voided: an invoice not already void.
    static func canVoid(_ document: Proposal) -> Bool { document.isInvoice && document.voidedAt == nil }

    /// Voids it: kept, owing nothing, its number never reused. Its payments
    /// stay with it (money that came in still came in).
    static func void(_ invoice: Proposal, note: String, now: Date = .now) {
        guard canVoid(invoice) else { return }
        invoice.voidedAt = now
        invoice.voidNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Numbers given out twice

    /// The note put on the later of two sent invoices with the same number.
    static func duplicateNote(_ number: String) -> String {
        "Another invoice also has the number \(number) (made on another device before they synced)."
    }

    /// The same number given out on two devices before iCloud brought them
    /// together: an unsent draft gets the next free number; two sent ones are
    /// never renumbered (the client has that number), and the later is noted.
    /// Run at launch, when iCloud brings changes and when the app comes back.
    /// Saves only if something changed.
    static func resolveDuplicateNumbers(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<Proposal>()) else { return }
        let invoices = all.filter { $0.isInvoice && !$0.isDeleted }
        var changed = false
        let groups = Dictionary(grouping: invoices) { "\($0.operatorID)\u{1F}\($0.invoiceNumber)" }
        for (_, group) in groups where group.count > 1 {
            let ordered = group.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            for later in ordered.dropFirst() {
                let number = later.invoiceNumber
                if !isIssued(later) {
                    later.invoiceNumber = InvoiceNumbering.next(operatorID: later.operatorID, in: context)
                    changed = true
                } else if !later.notes.contains(duplicateNote(number)) {
                    later.notes = later.notes.isEmpty ? duplicateNote(number) : later.notes + "\n" + duplicateNote(number)
                    changed = true
                }
            }
        }
        if changed { try? context.save() }
    }
}
