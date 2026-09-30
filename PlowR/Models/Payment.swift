import Foundation
import SwiftData

/// Money received against an invoice: how much, when, and how it was paid.
/// An invoice can be paid in parts; it's paid once its payments cover its
/// total (Payments.settle).
@Model
final class Payment {
    var id: UUID = UUID()
    var operatorID: String = ""
    /// A copy of the invoice's client, so a client's payments can be listed
    /// without going through their invoices.
    var clientID: String = ""
    var amount: Double = 0.0
    var receivedAt: Date = Date()
    /// How it was paid, as the business calls it: "Cash", "Check", "Venmo"...
    var method: String = ""
    /// A check number, a reference, anything worth keeping.
    var note: String = ""
    var createdAt: Date = Date()
    var invoice: Proposal?

    init(amount: Double, method: String, receivedAt: Date, operatorID: String) {
        self.amount = amount
        self.method = method
        self.receivedAt = receivedAt
        self.operatorID = operatorID
    }
}
