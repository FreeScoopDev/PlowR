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
    var visitID: String = ""      // scheduled visit this invoice was created from

    @Relationship(deleteRule: .cascade, inverse: \ProposalLineItem.proposal) var lineItems: [ProposalLineItem]?

    var subtotal: Double {
        (lineItems ?? []).reduce(0) { $0 + $1.lineTotal }
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
        InvoiceLines.roundedToCent(subtotal) - discountedTotal
    }

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

    var systemImage: String {
        switch self {
        case .proposal: return "doc.text"
        case .draft:    return "doc.badge.clock"
        case .sent:     return "paperplane.fill"
        case .paid:     return "checkmark.seal.fill"
        case .overdue:  return "exclamationmark.circle.fill"
        }
    }

    var chipColor: Color {
        switch self {
        case .proposal: return .blue
        case .draft:    return .gray
        case .sent:     return .orange
        case .paid:     return .green
        case .overdue:  return .red
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
                                   taxRate: Double) -> (discounted: Double, tax: Double, total: Double) {
        let discounted = InvoiceLines.roundedToCent(max(0, subtotal - max(0, discount)))
        let rate = taxRate.isFinite ? max(0, taxRate) : 0
        let tax = rate > 0 ? InvoiceLines.roundedToCent(discounted * rate / 100) : 0
        return (discounted, tax, discounted + tax)
    }

    /// A tax rate as the Edit screen shows it and the PDF prints it: up to three
    /// decimals, without trailing zeros (8.875, 8.5, 8). It was shown with one
    /// decimal, so opening Edit and tapping Done saved 8.875% as 8.9%.
    nonisolated static func percentText(_ rate: Double) -> String {
        var text = String(format: "%.3f", rate)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// A typed tax rate: a number from 0 to 100, otherwise 0.
    nonisolated static func taxRate(typed text: String) -> Double {
        guard let rate = Double(text.trimmingCharacters(in: .whitespaces)),
              rate.isFinite, (0...100).contains(rate) else { return 0 }
        return rate
    }

    /// A payment reminder to text the client. The amount is to the cent; it was
    /// rounded to whole dollars, so a $149.50 invoice was texted as $150. It was
    /// also written out separately on two screens.
    func reminderMessage(locale: Locale = .current) -> String {
        let amount = total.formatted(.currency(code: "USD").locale(locale))
        let statusWord = invoiceStatus == .overdue ? "overdue" : "outstanding"
        var message = "Hi \(clientName), just a friendly reminder that invoice \(invoiceNumber) for \(amount) is \(statusWord)."
        if let due = invoiceDueDate {
            message += " Due: \(due.formatted(.dateTime.month(.abbreviated).day().year().locale(locale)))."
        }
        message += " Please reach out if you have any questions — thank you!"
        return message
    }
}
