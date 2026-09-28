import SwiftUI
import SwiftData

struct ProposalEditView: View {
    @Bindable var proposal: Proposal
    @Environment(\.dismiss) private var dismiss

    /// The discount, tax and due date typed here. Only the ones changed are saved.
    @State private var edits: DocumentEdits

    init(proposal: Proposal) {
        self.proposal = proposal
        _edits = State(initialValue: DocumentEdits(discount: proposal.discountAmount, taxRate: proposal.taxRate,
                                                   dueDate: proposal.invoiceDueDate))
    }

    // Done, Mark as Sent and a swipe down all save, so the total shown is the
    // total the document will have.
    private func applyEdits() { edits.apply(to: proposal) }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                clientSection
                lineItemsSection
                invoiceDetailsSection
                if proposal.invoiceStatus == .draft {
                    markSentSection
                }
            }
            .navigationTitle(proposal.invoiceNumber)
            .navigationBarTitleDisplayMode(.inline)
            // Line amounts save as they're typed; a swipe down must keep the
            // discount, tax and due date changed here too, not just Done.
            .onDisappear { applyEdits() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyEdits()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section("Client") {
            LabeledContent("Name", value: proposal.clientName)
            if !proposal.clientAddress.isEmpty {
                LabeledContent("Address", value: proposal.clientAddress)
            }
        }
    }

    private var lineItemsSection: some View {
        Section {
            ForEach(proposal.sortedLineItems) { item in
                @Bindable var item = item
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.serviceName)
                            .font(.subheadline)
                        if !item.zoneLabel.isEmpty {
                            Text(item.zoneLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Text("$").foregroundStyle(.secondary).font(.subheadline)
                        // Shown and kept to the cent it's billed and printed at.
                        TextField("0.00", value: Binding(get: { InvoiceLines.roundedToCent(item.lineTotal) },
                                                         set: { item.lineTotal = InvoiceLines.roundedToCent($0) }),
                                  format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            LabeledContent("Total") {
                Text(String(format: "$%.2f", edits.total(of: proposal)))
                    .fontWeight(.bold)
            }
        } header: {
            Text("Line Items")
        } footer: {
            Text("Tap an amount to edit it.")
        }
    }

    private var invoiceDetailsSection: some View {
        Section("Invoice") {
            if proposal.isInvoice {
                DatePicker("Due Date", selection: $edits.dueDate, displayedComponents: .date)
            }
            HStack {
                Text("Discount $")
                Spacer()
                TextField("0.00", text: $edits.discountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text("Tax")
                Spacer()
                TextField("0.0", text: $edits.taxRateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("%").foregroundStyle(.secondary)
            }
            TextField("Notes", text: $proposal.notes, axis: .vertical)
                .lineLimit(3...)
        }
    }

    private var markSentSection: some View {
        Section {
            Button {
                // Keep the discount and tax typed on this screen: only Done saved them.
                applyEdits()
                proposal.invoiceSentAt = Date()
                dismiss()
            } label: {
                Label("Mark as Sent", systemImage: "paperplane.fill")
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Records the send date and starts the due date countdown.")
        }
    }
}
