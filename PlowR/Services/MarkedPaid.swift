import Foundation
import SwiftData

extension Payments {
    /// What one Mark Paid (`payInFull`) did, so its Undo can take back that
    /// and nothing else: the payment it recorded goes through
    /// `Payments.delete`, the way a payment recorded by mistake is taken back
    /// on the Payments screen, so what's owed is worked out the one way.
    /// Other payments on the invoice are never touched.
    struct MarkedPaid {
        let invoice: Proposal
        /// The payment it recorded; nil for an invoice with nothing owed,
        /// which is only marked paid (DocumentSent.markPaid).
        let payment: Payment?
        /// The payment as recorded: undo is refused once it's edited.
        let amount: Double
        let method: String
        let receivedAt: Date?
        /// `invoicePaidAt` after (before, it was nil: `payInFull` does nothing to a paid invoice).
        let paidAtAfter: Date?
        /// The invoice's client, whose `clientRespondedAt` marking paid may set.
        let client: Client?
        let respondedBefore: Date?
        let respondedAfter: Date?
        /// The invoice's payments after, by ID: one added or removed since
        /// means the money on it changed, and undo is refused.
        let paymentIDsAfter: Set<UUID>

        init(invoice: Proposal, payment: Payment?, client: Client?, respondedBefore: Date?) {
            self.invoice = invoice
            self.payment = payment
            amount = payment?.amount ?? 0
            method = payment?.method ?? ""
            receivedAt = payment?.receivedAt
            paidAtAfter = invoice.invoicePaidAt
            self.client = client
            self.respondedBefore = respondedBefore
            respondedAfter = client?.clientRespondedAt
            paymentIDsAfter = Set(Payments.live(invoice).map(\.id))
        }

        /// The toast's words: "Marked INV-0007 Paid · $120.00".
        var title: String {
            let name = invoice.invoiceNumber.isEmpty ? "Invoice" : invoice.invoiceNumber
            return payment == nil ? "Marked \(name) Paid" : "Marked \(name) Paid · \(Money.text(amount))"
        }

        var accessibilityLabel: String {
            "Undo marking \(invoice.invoiceNumber.isEmpty ? "the invoice" : invoice.invoiceNumber) paid"
        }

        /// Takes this Mark Paid back, if nothing changed since: the payment
        /// is still there as recorded, the invoice has the same payments and
        /// the same paid date. Otherwise `.changed`, with nothing touched.
        func undo(in context: ModelContext) -> UndoCenter.Result {
            guard !invoice.isGone, invoice.invoicePaidAt == paidAtAfter,
                  Set(Payments.live(invoice).map(\.id)) == paymentIDsAfter else { return .changed }
            if let payment {
                guard !payment.isGone, payment.invoice === invoice, payment.amount == amount,
                      payment.method == method, payment.receivedAt == receivedAt else { return .changed }
                Payments.delete(payment, in: context)
            } else {
                invoice.invoicePaidAt = nil
            }
            // Only if nothing else has marked them since (a reply, another payment).
            if let client, !client.isGone, client.clientRespondedAt == respondedAfter {
                client.clientRespondedAt = respondedBefore
            }
            try? context.save()
            return .undone
        }
    }
}
