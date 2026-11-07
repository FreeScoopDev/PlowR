import SwiftUI

/// One of the quick actions across the top of a client's page: a square,
/// tinted icon over its name. The row gives each tile an equal share of the
/// width. The tiles used to be a fixed 64 points wide, with icon boxes wider
/// than tall, in a row that stopped short of the edge.
struct ClientActionTile: View {
    let title: String
    let icon: String
    let color: Color
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 48

    /// Grows with the text at accessibility sizes, by at most half again.
    private var side: CGFloat { typeSize.isAccessibilitySize ? min(scaledSide, 72) : 48 }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: side * 20 / 48, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: side, height: side)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(PlowRColor.inkSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                .multilineTextAlignment(.center)
                // Two to a row, "Schedule" is as wide as a cell at the
                // largest sizes: stop growing there rather than break the word.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
