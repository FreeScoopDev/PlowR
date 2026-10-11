import Foundation
import SwiftData
import SwiftUI

@Model
final class Proposal {
    var id: UUID = UUID()
    var operatorID: String = ""
    var clientID: String = ""
    var clientName: String = ""
    var clientAddress: String = ""
    var clientPhone: String = ""
    var notes: String = ""
    var discountAmount: Double = 0.0
    var taxRate: Double = 0.0
    var disclaimer: String = ""
    var validUntil: Date?
    var createdAt: Date = Date()

    var invoiceNumber: String = ""
    var invoiceDueDate: Date?
    var invoiceSentAt: Date?
    var invoicePaidAt: Date?
    var revisionOf: String = ""
    /// Voided: kept as a record (its number is never used again) and owing
    /// nothing. A revised invoice is voided by its revision (InvoiceRecords).
    var voidedAt: Date?
    /// Why: "Revised as INV-0042-R1", or what the business wrote.
    var voidNote: String = ""
    var visitID: String = ""      // scheduled visit this invoice was created from
    /// An installment of a contract (ContractInstallments): its contract,
    /// and which payment (1, 2, …). Empty for any other invoice.
    var contractID: String = ""
    var installmentIndex: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \ProposalLineItem.proposal) var lineItems: [ProposalLineItem]?
    /// Money received against it, in parts or all at once (Payments).
    @Relationship(deleteRule: .cascade, inverse: \Payment.invoice) var payments: [Payment]?

    /// The sum of the lines as billed: each to the cent, as the PDF prints
    /// them, so the printed rows add up to the printed sub-total.
    var subtotal: Double {
        InvoiceLines.roundedToCent((lineItems ?? []).reduce(0) { $0 + InvoiceLines.roundedToCent($1.lineTotal) })
    }

    var discountedTotal: Double {
        Self.totals(subtotal: subtotal, discount: discountAmount, taxRate: taxRate).discounted
    }

    var taxAmount: Double {
        Self.totals(subtotal: subtotal, discount: discountAmount, taxRate: taxRate).tax
    }

    var total: Double {
        Self.totals(subtotal: subtotal, discount: discountAmount, taxRate: taxRate).total
    }

    /// The discount actually taken off: never more than the subtotal. The PDF
    /// printed the discount as entered, so its rows didn't add up when a
    /// discount exceeded the subtotal.
    var appliedDiscount: Double {
        subtotal - discountedTotal
    }

    /// Its payments, oldest first.
    var sortedPayments: [Payment] {
        (payments ?? []).sorted { ($0.receivedAt, $0.createdAt) < ($1.receivedAt, $1.createdAt) }
    }

    /// What its payments add up to.
    var paymentsTotal: Double {
        InvoiceLines.roundedToCent((payments ?? []).reduce(0) { $0 + $1.amount })
    }

    /// What's been paid: its payments, and a paid invoice at least its total
    /// (one marked paid before payments were kept, or on a device with an
    /// older PlowR, has fewer or none). More, if it was overpaid.
    var amountPaid: Double {
        guard isInvoice else { return 0 }
        // A voided invoice's "paid" was moved to its revision as a payment
        // (ServiceLog.movePayments): only what's still recorded on it counts.
        return invoicePaidAt != nil && voidedAt == nil ? max(total, paymentsTotal) : paymentsTotal
    }

    /// Paid more than its total (edited down after it was paid, or the same
    /// payment recorded on two devices).
    var overpaid: Double {
        isInvoice ? max(0, InvoiceLines.roundedToCent(paymentsTotal - total)) : 0
    }

    /// What the client still owes on it: nothing on a proposal or a paid invoice.
    var balanceDue: Double {
        guard isInvoice, invoicePaidAt == nil, voidedAt == nil else { return 0 }
        return max(0, InvoiceLines.roundedToCent(total - amountPaid))
    }

    /// Paid in part: some money received, some still owed.
    var isPartlyPaid: Bool { balanceDue > 0 && amountPaid > 0 }

    var sortedLineItems: [ProposalLineItem] {
        (lineItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var isInvoice: Bool { !invoiceNumber.isEmpty }

    /// Copies for a revision or a duplicate. Each copy keeps the original's
    /// amount: a line's total can differ from quantity × unit price (a typed
    /// amount, an edit, a zone's share of a whole-property price), and letting
    /// the initializer recompute it silently repriced the copy.
    func makeLineItemCopies() -> [ProposalLineItem] {
        (lineItems ?? []).map { item in
            let copy = ProposalLineItem(
                serviceName: item.serviceName,
                zoneLabel: item.zoneLabel,
                quantity: item.quantity,
                unitType: item.unitType,
                unitPrice: item.unitPrice,
                sortOrder: item.sortOrder,
                itemNotes: item.itemNotes
            )
            copy.lineTotal = item.lineTotal
            return copy
        }
    }

    var invoiceStatus: InvoiceStatus {
        guard isInvoice else { return .proposal }
        if voidedAt != nil { return .void }
        if invoicePaidAt != nil { return .paid }
        if let due = invoiceDueDate, due < Date(), invoiceSentAt != nil { return .overdue }
        if invoiceSentAt != nil { return .sent }
        return .draft
    }

    init(operatorID: String, client: Client) {
        self.operatorID = operatorID
        self.clientID = client.id.uuidString
        self.clientName = client.name
        self.clientAddress = client.address
        self.clientPhone = client.phone
    }
}

enum InvoiceStatus: String {
    case proposal = "Proposal"
    case draft    = "Draft Invoice"
    case sent     = "Sent"
    case paid     = "Paid"
    case overdue  = "Overdue"
    case void     = "Void"

    var systemImage: String {
        switch self {
        case .proposal: return "doc.text"
        case .draft:    return "doc.badge.clock"
        case .sent:     return "paperplane.fill"
        case .paid:     return "checkmark.seal.fill"
        case .overdue:  return "exclamationmark.circle.fill"
        case .void:     return "xmark.circle"
        }
    }

    var chipColor: Color {
        switch self {
        case .proposal: return .blue
        case .draft:    return .gray
        case .sent:     return .orange
        case .paid:     return .green
        case .overdue:  return .red
        case .void:     return .secondary
        }
    }
}

// MARK: - Totals, tax rate text, reminders

extension Proposal {

    /// A document's totals from its parts. The one formula, used by the saved
    /// document, the PDF, and every screen that shows a total before saving:
    /// the discount comes off the subtotal (never below zero), then tax is
    /// charged on what's left, rounded to the cent. The builder's estimate used
    /// to leave out tax and custom lines, and the Edit screen took the discount
    /// off a second time.
    nonisolated static func totals(subtotal: Double, discount: Double,
                                   taxRate: Double) -> (subtotal: Double, discounted: Double, tax: Double, total: Double) {
        let sub = InvoiceLines.roundedToCent(subtotal)
        let discounted = InvoiceLines.roundedToCent(max(0, sub - max(0, discount)))
        let rate = taxRate.isFinite ? max(0, taxRate) : 0
        let tax = rate > 0 ? InvoiceLines.roundedToCent(discounted * rate / 100) : 0
        return (sub, discounted, tax, InvoiceLines.roundedToCent(discounted + tax))
    }

    /// A tax rate as the Edit screen shows it and the PDF prints it, without
    /// trailing zeros (8.875, 8.5, 8). It was shown with one decimal, so opening
    /// Edit and tapping Done saved 8.875% as 8.9%. Rates are saved to three
    /// decimals, but an older one can hold four (7.0625), so up to four are
    /// shown: the label always states the rate charged.
    nonisolated static func percentText(_ rate: Double) -> String {
        DecimalText.trimmed(rate)
    }

    /// A typed tax rate: a number from 0 to 100, kept to three decimals so the
    /// rate charged, the Edit field and the PDF label always agree; otherwise 0.
    nonisolated static func taxRate(typed text: String) -> Double {
        readTaxRate(text) ?? 0
    }

    /// The rate in `text`, or nil when it isn't a number from 0 to 100 (empty
    /// text is no rate, 0). Business Profile won't save a rate it can't read:
    /// every new invoice would go out at 0% without a word.
    nonisolated static func readTaxRate(_ text: String) -> Double? {
        // A decimal comma ("6,625") is what the keypad types in many regions.
        // Read in every region: a rate is at most 100, so a comma in one
        // can't be separating thousands.
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        guard let rate = DecimalText.number(text, decimalComma: true), (0...100).contains(rate) else { return nil }
        return (rate * 1000).rounded() / 1000
    }

    /// A payment reminder to text the client. The amount is to the cent; it was
    /// rounded to whole dollars, so a $149.50 invoice was texted as $150. It was
    /// also written out separately on two screens.
    /// Paid in part, it asks for the balance, as the PDF does.
    func reminderMessage(locale: Locale = .current) -> String {
        let statusWord = invoiceStatus == .overdue ? "overdue" : "outstanding"
        var message: String
        if isPartlyPaid {
            let balance = balanceDue.formatted(.currency(code: "USD").locale(locale))
            message = "Hi \(clientName), just a friendly reminder that the balance of \(balance) on invoice \(invoiceNumber) is \(statusWord)."
        } else {
            let amount = total.formatted(.currency(code: "USD").locale(locale))
            message = "Hi \(clientName), just a friendly reminder that invoice \(invoiceNumber) for \(amount) is \(statusWord)."
        }
        if let due = invoiceDueDate {
            message += " Due: \(due.formatted(.dateTime.month(.abbreviated).day().year().locale(locale)))."
        }
        message += " Please reach out if you have any questions — thank you!"
        return message
    }
}
