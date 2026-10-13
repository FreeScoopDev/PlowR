import SwiftUI

/// A short status in a capsule: an invoice's or a visit's status, a count,
/// "Revision", "After Hours". Every status chip is drawn this way, in its
/// status's soft and text colours (`PlowRColor.Status`, 1.7), and always says
/// its word, so colour is never the only signal. Selectable chips and map
/// buttons are controls, not statuses, and are drawn their own way.
struct StatusChip: View {
    let text: String
    var systemImage: String?
    let status: PlowRColor.Status

    init(_ text: String, systemImage: String? = nil, status: PlowRColor.Status) {
        self.text = text
        self.systemImage = systemImage
        self.status = status
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(status.text)
        .padding(.horizontal, PlowRLayout.space2)
        .padding(.vertical, 3)
        .background(status.soft, in: Capsule())
        // A status cut off ("After Ho…") says nothing: the row's other
        // content gives way instead.
        .fixedSize()
    }
}

/// The tag on a visit photo's thumbnail: Before, After or Below Trigger, as a
/// status chip (its text on its soft fill, 4.5:1 in light and dark,
/// `DesignTokensTests`), in a text style that grows with the user's text
/// size. It was 9 pt white on orange or green (about 2.2:1), and those
/// colours mean owed and done on invoices: Before is neutral now, After is
/// done (the work is). Capped at the first accessibility size so the tag
/// can't cover the photo it labels.
struct PhotoTag: View {
    let photo: StopPhoto

    var body: some View {
        StatusChip(photo.kindLabel, systemImage: symbol, status: photo.tagStatus)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(PlowRLayout.space1)
    }

    private var symbol: String {
        photo.isCheckPhoto ? "arrow.down.circle" : photo.isBefore ? "clock" : "checkmark"
    }
}

extension StopPhoto {
    /// A photo's status colour: After is done; Before and Below Trigger say
    /// nothing about money or state, so they're neutral.
    var tagStatus: PlowRColor.Status {
        !isCheckPhoto && !isBefore ? .done : .neutral
    }
}
