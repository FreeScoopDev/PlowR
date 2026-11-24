import SwiftData
import SwiftUI

/// Mark Paid from one tap (a client's page, the Documents list) asks first
/// and says what it will record: a mini button brushed in passing used to
/// mark an invoice paid with nothing to show it had.
enum MarkPaidPrompt {
    static func title(for invoice: Proposal) -> String {
        invoice.invoiceNumber.isEmpty ? "Mark This Invoice Paid?" : "Mark \(invoice.invoiceNumber) Paid?"
    }

    /// What `Payments.payInFull` will do: record the balance today, or, with
    /// nothing owed, just mark it paid.
    static func message(for invoice: Proposal) -> String {
        let balance = invoice.balanceDue
        return balance > 0
            ? "Records a payment of \(Money.text(balance)) today."
            : "Nothing is owed on it, so it's simply marked paid."
    }
}

extension View {
    /// Asks before marking `invoice` paid; Mark Paid records it
    /// (`Payments.payInFull`, unchanged) with a success haptic, and offers
    /// Undo (`UndoCenter.markPaid`). Both stay (Joe, 2026-11-24).
    func markPaidConfirmation(_ invoice: Binding<Proposal?>) -> some View {
        modifier(MarkPaidConfirmation(invoice: invoice))
    }
}

private struct MarkPaidConfirmation: ViewModifier {
    @Binding var invoice: Proposal?
    @Environment(UndoCenter.self) private var undoCenter

    func body(content: Content) -> some View {
        content
            .confirmationDialog(invoice.map { MarkPaidPrompt.title(for: $0) } ?? "",
                                isPresented: Binding(get: { invoice != nil },
                                                     set: { if !$0 { invoice = nil } }),
                                titleVisibility: .visible, presenting: invoice) { document in
                Button("Mark Paid") {
                    undoCenter.markPaid(document)
                    Haptics.success()
                }
                Button("Cancel", role: .cancel) { }
            } message: { document in
                Text(MarkPaidPrompt.message(for: document))
            }
    }
}
