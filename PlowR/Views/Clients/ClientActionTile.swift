import SwiftUI

/// One of the quick actions across the top of a client's page: a square,
/// tinted icon over its name. The row gives each tile an equal share of the
/// width. The tiles used to be a fixed 64 points wide, with icon boxes wider
/// than tall, in a row that stopped short of the edge.
struct ClientActionTile: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
