import SwiftUI
import SwiftData

struct ProposalEditView: View {
    @Bindable var proposal: Proposal
    @Environment(\.dismiss) private var dismiss

    @State private var dueDate: Date
    @State private var discountString: String
    @State private var taxRateString: String

    init(proposal: Proposal) {
        self.proposal = proposal
        _dueDate = State(initialValue: proposal.invoiceDueDate ?? Date().addingTimeInterval(30 * 86400))
        _discountString = State(initialValue: proposal.discountAmount > 0 ? String(format: "%.2f", proposal.discountAmount) : "")
        _taxRateString = State(initialValue: proposal.taxRate > 0 ? Proposal.percentText(proposal.taxRate) : "")
    }

    // What Done saves, so the total shown is the total that will be saved.
    private var pendingDiscount: Double { max(0, InvoiceLines.price(typed: discountString, default: 0)) }
    private var pendingTaxRate: Double { Proposal.taxRate(typed: taxRateString) }
    private var pendingTotal: Double {
        Proposal.totals(subtotal: proposal.subtotal, discount: pendingDiscount, taxRate: pendingTaxRate).total
    }

    private func applyEdits() {
        proposal.invoiceDueDate = dueDate
        proposal.discountAmount = pendingDiscount
        proposal.taxRate = pendingTaxRate
    }

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
                        TextField("0.00", value: $item.lineTotal, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            LabeledContent("Total") {
                Text(String(format: "$%.2f", pendingTotal))
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
                DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
            }
            HStack {
                Text("Discount $")
                Spacer()
                TextField("0.00", text: $discountString)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text("Tax")
                Spacer()
                TextField("0.0", text: $taxRateString)
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
