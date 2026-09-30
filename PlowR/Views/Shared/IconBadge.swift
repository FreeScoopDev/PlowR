import SwiftUI

/// A symbol in a softly tinted rounded square: a row's or a tile's icon.
/// The client page's quick actions use the same look at 48 points.
struct IconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            .accessibilityHidden(true)
    }
}
