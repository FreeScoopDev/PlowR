import SwiftUI
import SwiftData

struct ProposalRowView: View {
    let proposal: Proposal

    private var status: InvoiceStatus { proposal.invoiceStatus }

    var body: some View {
        HStack(spacing: 12) {
            // Left accent bar — mirrors the visit row pattern
            AccentBar(status: status.chipStatus)

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
                            .foregroundStyle(status == .overdue ? PlowRColor.Status.overdue.text : Color(.tertiaryLabel))
                    } else {
                        Text(proposal.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.text(proposal.total))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                StatusChip(status.rawValue, systemImage: status.systemImage, status: status.chipStatus)

                // Paid in part: what's still owed.
                BalanceDueCaption(document: proposal)

                if !proposal.isInvoice, let expiry = proposal.validUntil {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: expiry).day ?? Int.max
                    if daysLeft >= 0 && daysLeft <= 3 {
                        StatusChip(daysLeft == 0 ? "Expires today" : "Expires in \(daysLeft)d",
                                   systemImage: "clock.badge.exclamationmark", status: .owed)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
