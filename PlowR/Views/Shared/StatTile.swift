import SwiftUI

/// A number with its label, taking an equal share of its row
/// (`StatTileRow`). Every summary of counts and money uses it: the
/// Dashboard's, the Clients and Documents summaries, the Season Report, a
/// route's load-out and recap. A tile with a status (owed, overdue, done…)
/// sits on that status's soft colour with the number in its text colour; a
/// tile without one, or a zero, is plain (`PlowRColor.Status`, 1.7).
struct StatTile: View {
    let value: String
    let label: String
    var status: PlowRColor.Status?

    init(value: String, label: String, status: PlowRColor.Status? = nil) {
        self.value = value
        self.label = label
        self.status = status
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous)
        VStack(spacing: PlowRLayout.space1) {
            Text(value)
                .font(PlowRFont.title)
                .monospacedDigit()
                .foregroundStyle(status?.text ?? PlowRColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(PlowRColor.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PlowRLayout.space3)
        .padding(.horizontal, PlowRLayout.space2)
        .background(status?.soft ?? PlowRColor.surface, in: shape)
        .overlay(shape.strokeBorder(status == nil ? PlowRColor.line : .clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Stat tiles side by side, sharing the width.
struct StatTileRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: PlowRLayout.tileSpacing) { content }
            // A point of room, so an outlined tile's edge isn't clipped by
            // a list row that ends exactly at the row.
            .padding(1)
    }
}
