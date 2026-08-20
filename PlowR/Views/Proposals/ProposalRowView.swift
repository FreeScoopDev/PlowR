import SwiftUI
import SwiftData

struct ProposalRowView: View {
    let proposal: Proposal

    private var status: InvoiceStatus { proposal.invoiceStatus }

    var body: some View {
        HStack(spacing: 12) {
            // Left accent bar — mirrors the visit row pattern
            RoundedRectangle(cornerRadius: 3)
                .fill(status.chipColor)
                .frame(width: 4, height: 48)

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

                Label(status.rawValue, systemImage: status.systemImage)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(status.chipColor.opacity(0.13))
                    .foregroundStyle(status.chipColor)
                    .clipShape(Capsule())

                if !proposal.isInvoice, let expiry = proposal.validUntil {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: expiry).day ?? Int.max
                    if daysLeft >= 0 && daysLeft <= 3 {
                        Label(daysLeft == 0 ? "Expires today" : "Expires in \(daysLeft)d", systemImage: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.13))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
