import SwiftUI
import SwiftData

struct ProposalRowView: View {
    let proposal: Proposal

    private var status: InvoiceStatus { proposal.invoiceStatus }

    var body: some View {
        HStack(spacing: 12) {
            // Left accent bar — mirrors the visit row pattern
            AccentBar(color: status.chipColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.clientName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !proposal.clientAddress.isEmpty {
                    Text(proposal.clientAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if proposal.isInvoice && !proposal.invoiceNumber.isEmpty {
                        Text(proposal.invoiceNumber)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let due = proposal.invoiceDueDate {
                        Text(proposal.isInvoice ? "· Due \(due.formatted(.dateTime.month(.abbreviated).day()))" : "")
                            .font(.caption2)
                            .foregroundStyle(status == .overdue ? Color.red : Color(.tertiaryLabel))
                    } else {
                        Text(proposal.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "$%.2f", proposal.total))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                StatusChip(status.rawValue, systemImage: status.systemImage, color: status.chipColor)

                if !proposal.isInvoice, let expiry = proposal.validUntil {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: expiry).day ?? Int.max
                    if daysLeft >= 0 && daysLeft <= 3 {
                        StatusChip(daysLeft == 0 ? "Expires today" : "Expires in \(daysLeft)d",
                                   systemImage: "clock.badge.exclamationmark", color: .orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
