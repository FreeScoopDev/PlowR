import SwiftData
import SwiftUI

/// An invoice's payments: what's been paid and what's still owed, each
/// payment received (swipe to take one back), and recording a new one: all
/// that's owed, or part of it.
struct InvoicePaymentsView: View {
    @Bindable var invoice: Proposal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allPaymentMethods: [PaymentMethod]

    @State private var amount = ""
    @State private var method = ""
    @State private var receivedAt = Date()
    @State private var note = ""

    private var methods: [String] {
        Payments.methods(allPaymentMethods.filter { $0.operatorID == invoice.operatorID })
    }

    /// The amount typed, when it's one that can be recorded.
    private var typedAmount: Double? {
        let value = InvoiceLines.price(typed: amount, default: 0)
        return value > 0 && value <= invoice.balanceDue + Payments.tolerance ? value : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Invoice Total") { money(invoice.total) }
                    LabeledContent("Paid") { money(invoice.amountPaid) }
                    LabeledContent("Balance Due") {
                        money(invoice.balanceDue)
                            .fontWeight(.semibold)
                            .foregroundStyle(invoice.balanceDue > 0 ? .orange : .green)
                    }
                    if invoice.overpaid > 0 {
                        LabeledContent("Overpaid") { money(invoice.overpaid).foregroundStyle(.purple) }
                    }
                } footer: {
                    if invoice.overpaid > 0 {
                        Text("Its payments come to more than its total: one may have been recorded twice.")
                    }
                }
                // Nothing left to pay but not marked paid (edited down, say).
                if invoice.balanceDue <= 0, invoice.invoicePaidAt == nil {
                    Section {
                        Button("Mark Paid") { Payments.payInFull(invoice, in: modelContext) }
                    } footer: {
                        Text("Nothing is left to pay on this invoice.")
                    }
                }
                paymentsSection
                if invoice.balanceDue > 0 { recordSection }
            }
            .navigationTitle("Payments")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: resetForm)
        }
    }

    @ViewBuilder
    private var paymentsSection: some View {
        let payments = invoice.sortedPayments
        if !payments.isEmpty {
            Section {
                ForEach(payments) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.receivedAt, format: .dateTime.month(.abbreviated).day().year())
                            let detail = [payment.method, payment.note].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        money(payment.amount)
                    }
                }
                .onDelete { offsets in
                    offsets.map { payments[$0] }.forEach { Payments.delete($0, in: modelContext) }
                    resetForm()
                }
            } header: {
                Text("Received")
            } footer: {
                Text("Swipe left to remove a payment recorded by mistake. What it paid is owed again.")
            }
        } else if let paidAt = invoice.invoicePaidAt {
            Section("Received") {
                LabeledContent("Marked paid", value: paidAt.formatted(.dateTime.month(.abbreviated).day().year()))
            }
        }
    }

    private var recordSection: some View {
        Section {
            LabeledContent("Amount") {
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Picker("Paid By", selection: $method) {
                Text("Not Recorded").tag("")
                ForEach(methods, id: \.self) { Text($0).tag($0) }
            }
            DatePicker("Received", selection: $receivedAt, in: ...Date.now, displayedComponents: .date)
            TextField("Note (check number, reference…)", text: $note)
            Button("Record Payment") { record() }
                .disabled(typedAmount == nil)
        } header: {
            Text("Record a Payment")
        } footer: {
            Text(recordFooter)
        }
    }

    private var recordFooter: String {
        let owed = invoice.balanceDue.formatted(.currency(code: "USD"))
        if InvoiceLines.price(typed: amount, default: 0) > invoice.balanceDue + Payments.tolerance {
            return "That's more than the \(owed) owed."
        }
        return "All that's owed (\(owed)), or part of it. Paid in full, the invoice is marked paid."
    }

    private func money(_ value: Double) -> Text {
        Text(value, format: .currency(code: "USD"))
    }

    private func record() {
        guard let value = typedAmount else { return }
        Payments.record(value, method: method, note: note, receivedAt: receivedAt, on: invoice, in: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if invoice.balanceDue <= 0 { dismiss() } else { resetForm() }
    }

    /// Ready for the next payment: what's still owed, by the client's usual method.
    private func resetForm() {
        amount = invoice.balanceDue > 0 ? StopRecording.money(invoice.balanceDue) : ""
        method = Payments.preferredMethod(for: invoice, in: modelContext)
        receivedAt = Date()
        note = ""
    }
}
