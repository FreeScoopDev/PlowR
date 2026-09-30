import SwiftUI

/// A number with its label, on a soft tint of the number's colour, taking an
/// equal share of its row (`StatTileRow`). Every summary of counts and money
/// uses it: the Dashboard's finances, the Clients and Documents summaries,
/// the Season Report and the route recap. They used to be drawn four ways:
/// grey or tinted, radius 12 or 14, with or without a shadow, some unboxed,
/// and one that could cut off a large amount.
struct StatTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous)
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(color.opacity(0.1), in: shape)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Stat tiles side by side, sharing the width.
struct StatTileRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: PlowRLayout.tileSpacing) { content }
    }
}
