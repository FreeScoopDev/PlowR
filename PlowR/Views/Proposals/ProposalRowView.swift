import SwiftUI
import SwiftData

struct ProposalRowView: View {
    let proposal: Proposal

    private var status: InvoiceStatus { proposal.invoiceStatus }

    // MARK: - Body

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(proposal.clientName)
                        .font(.headline)
                    statusChip
                }
                Text(proposal.clientAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if proposal.isInvoice {
                    HStack(spacing: 4) {
                        Text(proposal.invoiceNumber)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if let due = proposal.invoiceDueDate {
                            Text("· Due \(due, style: .date)")
                                .font(.caption2)
                                .foregroundStyle(status == .overdue ? Color.red : Color(.tertiaryLabel))
                        }
                    }
                } else {
                    Text(proposal.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(String(format: "$%.2f", proposal.total))
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status Chip

    @ViewBuilder
    private var statusChip: some View {
        Label(status.rawValue, systemImage: status.systemImage)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.chipColor.opacity(0.15))
            .foregroundStyle(status.chipColor)
            .clipShape(Capsule())
    }
}
