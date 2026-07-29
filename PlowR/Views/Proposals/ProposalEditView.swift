import SwiftUI
import SwiftData

struct ProposalEditView: View {
    @Bindable var proposal: Proposal
    @Environment(\.dismiss) private var dismiss

    @State private var dueDate: Date

    init(proposal: Proposal) {
        self.proposal = proposal
        _dueDate = State(initialValue: proposal.invoiceDueDate ?? Date().addingTimeInterval(30 * 86400))
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
                        proposal.invoiceDueDate = dueDate
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
                Text(String(format: "$%.2f", proposal.total))
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
            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
            TextField("Notes", text: $proposal.notes, axis: .vertical)
                .lineLimit(3...)
        }
    }

    private var markSentSection: some View {
        Section {
            Button {
                proposal.invoiceDueDate = dueDate
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
