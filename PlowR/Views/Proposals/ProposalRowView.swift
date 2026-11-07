import SwiftUI
import SwiftData

struct ProposalRowView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let proposal: Proposal

    private var status: InvoiceStatus { proposal.invoiceStatus }

    var body: some View {
        // Large text: the title, then its details, then the amount and
        // status under them (`AdaptiveRow`).
        let large = typeSize.isAccessibilitySize
        AdaptiveRow {
            // Left accent bar — mirrors the visit row pattern
            AccentBar(status: status.chipStatus)
        } main: {
            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.clientName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(large ? nil : 1)
                if !proposal.clientAddress.isEmpty {
                    Text(proposal.clientAddress)
                        .font(.caption)
                        .foregroundStyle(PlowRColor.inkSecondary)
                        .lineLimit(large ? nil : 1)
                }
                AdaptiveDetails {
                    if proposal.isInvoice && !proposal.invoiceNumber.isEmpty {
                        Text(proposal.invoiceNumber)
                            .font(.caption2)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                    if let due = proposal.invoiceDueDate {
                        Text(proposal.isInvoice ? "\(large ? "" : "· ")Due \(due.formatted(.dateTime.month(.abbreviated).day()))" : "")
                            .font(.caption2)
                            .foregroundStyle(status == .overdue ? PlowRColor.Status.overdue.text : PlowRColor.inkSecondary)
                    } else {
                        Text(proposal.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption2)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                }
            }
        } trailing: {
            VStack(alignment: typeSize.trailingColumnAlignment, spacing: 4) {
                Text(Money.text(proposal.total))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    // An amount stays on one line; at the largest sizes it scales
                    // down a little rather than break.
                    .lineLimit(large ? 1 : nil)
                    .minimumScaleFactor(large ? 0.6 : 1)

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
