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
