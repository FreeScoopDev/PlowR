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

    @Relationship(deleteRule: .cascade, inverse: \ProposalLineItem.proposal) var lineItems: [ProposalLineItem]?

    var subtotal: Double {
        (lineItems ?? []).reduce(0) { $0 + $1.lineTotal }
    }

    var discountedTotal: Double {
        max(0, subtotal - discountAmount)
    }

    var taxAmount: Double {
        taxRate > 0 ? discountedTotal * taxRate / 100 : 0
    }

    var total: Double {
        discountedTotal + taxAmount
    }

    var sortedLineItems: [ProposalLineItem] {
        (lineItems ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var isInvoice: Bool { !invoiceNumber.isEmpty }

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
