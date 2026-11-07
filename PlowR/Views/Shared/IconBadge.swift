import SwiftUI

/// A symbol in a softly tinted rounded square: a row's or a tile's icon.
/// The brand, or a status's colours when the row is about
/// one (`PlowRColor.Status`: owed, overdue…). The client page's quick
/// actions use the same look at 48 points.
struct IconBadge: View {
    let systemImage: String
    var status: PlowRColor.Status?
    var size: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 40

    init(systemImage: String, status: PlowRColor.Status? = nil, size: CGFloat = 40) {
        self.systemImage = systemImage
        self.status = status
        self.size = size
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    /// Grows with the text at accessibility sizes, to at most half again
    /// its size, so it doesn't dwarf the text it sits by. Other sizes keep
    /// the size it was given.
    private var side: CGFloat {
        typeSize.isAccessibilitySize ? min(scaledSize, size * 1.5) : size
    }

    var body: some View {
        let size = side
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(status?.text ?? PlowRColor.brand)
            .frame(width: size, height: size)
            .background(status?.soft ?? PlowRColor.brand.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            .accessibilityHidden(true)
    }
}
