import Foundation
import SwiftData

/// What a document's Edit screen saves: the discount, the tax rate and, for an
/// invoice, the due date.
///
/// The screen saves on swipe-down as well as on Done, and its fields show the
/// stored values rounded: the discount to the cent, the tax rate to three
/// decimals. Saving every field would change an older document that holds a
/// finer value just by opening the screen, and would put back a value another
/// device changed meanwhile. So only the fields the user changed are saved.
///
/// `nonisolated`: plain values, used from the view and from tests.
nonisolated struct DocumentEdits {
    var discountText: String
    var taxRateText: String
    var dueDate: Date

    private let openedDiscountText: String
    private let openedTaxRateText: String
    private let openedDueDate: Date

    /// `termsDays`: the business's terms (InvoiceTerms.days(for:)).
    init(discount: Double, taxRate: Double, dueDate: Date?, termsDays: Int = InvoiceTerms.days, now: Date = Date()) {
        openedDiscountText = discount > 0 ? String(format: "%.2f", discount) : ""
        openedTaxRateText = taxRate > 0 ? Proposal.percentText(taxRate) : ""
        // An invoice without a due date shows one on the business's terms,
        // and saving keeps it.
        openedDueDate = dueDate ?? InvoiceTerms.dueDate(from: now, days: termsDays)
        discountText = openedDiscountText
        taxRateText = openedTaxRateText
        self.dueDate = openedDueDate
    }

    /// The discount typed, or nil if the field is as it opened or can't be
    /// read (the stored discount stays; the screen says so).
    var typedDiscount: Double? {
        guard discountText != openedDiscountText, !discountUnreadable else { return nil }
        return max(0, InvoiceLines.price(typed: discountText, default: 0))
    }

    /// The discount typed can't be read.
    var discountUnreadable: Bool { discountText != openedDiscountText && InvoiceLines.isUnreadable(discountText) }
    /// The tax rate typed isn't a rate from 0 to 100.
    var taxUnreadable: Bool { taxRateText != openedTaxRateText && Proposal.readTaxRate(taxRateText) == nil }

    /// The tax rate typed, in percent, or nil if the field is as it opened or
    /// isn't a rate from 0 to 100 (the stored rate stays; the screen says so).
    var typedTaxRate: Double? {
        taxRateText == openedTaxRateText ? nil : Proposal.readTaxRate(taxRateText)
    }

    /// The fields typed that can't be read, as the screen names them. They aren't saved.
    var unreadableFields: [String] {
        (discountUnreadable ? ["Discount"] : []) + (taxUnreadable ? ["Tax"] : [])
    }
}

extension DocumentEdits {
    /// The Edit screen's fields for `proposal`, on its business's terms
    /// (its profile found by BusinessProfiles.current in its own context).
    @MainActor
    init(editing proposal: Proposal, now: Date = Date()) {
        let profiles = (try? proposal.modelContext?.fetch(FetchDescriptor<BusinessProfile>())) ?? []
        self.init(editing: proposal, termsDays: Self.termsDays(for: proposal, profiles: profiles), now: now)
    }

    /// The Edit screen's fields for `proposal` on terms of `termsDays`
    /// (`termsDays(for:profiles:)`): no database read, so the screen's init,
    /// run on every redraw of the screen that shows it, stays cheap.
    @MainActor
    init(editing proposal: Proposal, termsDays: Int, now: Date = Date()) {
        self.init(discount: proposal.discountAmount, taxRate: proposal.taxRate, dueDate: proposal.invoiceDueDate,
                  termsDays: termsDays, now: now)
    }

    /// `proposal`'s business's terms, its profile found among `profiles`
    /// (BusinessProfiles.current), as the screen showing it already has them.
    @MainActor
    static func termsDays(for proposal: Proposal, profiles: [BusinessProfile]) -> Int {
        InvoiceTerms.days(for: BusinessProfiles.current(profiles, operatorID: proposal.operatorID))
    }

    /// The total `proposal` will have once these edits are saved.
    @MainActor
    func total(of proposal: Proposal) -> Double {
        Proposal.totals(subtotal: proposal.subtotal,
                        discount: typedDiscount ?? proposal.discountAmount,
                        taxRate: typedTaxRate ?? proposal.taxRate).total
    }

    /// Saves the fields the user changed into `proposal`. An invoice without a
    /// due date also gets the one the screen showed.
    @MainActor
    func apply(to proposal: Proposal) {
        if let discount = typedDiscount, proposal.discountAmount != discount { proposal.discountAmount = discount }
        if let rate = typedTaxRate, proposal.taxRate != rate { proposal.taxRate = rate }
        if proposal.isInvoice, proposal.invoiceDueDate != dueDate,
           dueDate != openedDueDate || proposal.invoiceDueDate == nil {
            proposal.invoiceDueDate = dueDate
        }
    }

    /// Saves them, and the invoice's payments are weighed against its new
    /// total (Payments.settle): edited down to what's been paid, it's paid;
    /// its line amounts, changed on the same screen, count too.
    @MainActor
    func apply(to proposal: Proposal, in context: ModelContext) {
        apply(to: proposal)
        Payments.settle(proposal, in: context)
    }
}
