import SwiftUI

/// A short status in a tinted capsule: an invoice's or a visit's status, a
/// count, "Revision", "After Hours". Every status chip is drawn this way. They
/// used to vary in weight (regular or semibold), padding (5–8 by 2–3), size
/// (caption or caption2) and tint (0.12 to 0.15), sometimes on the same
/// screen. Selectable chips and map buttons are controls, not statuses, and
/// are drawn their own way.
struct StatusChip: View {
    let text: String
    var systemImage: String?
    let color: Color

    init(_ text: String, systemImage: String? = nil, color: Color) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        // A status cut off ("After Ho…") says nothing: the row's other
        // content gives way instead.
        .fixedSize()
    }
}
