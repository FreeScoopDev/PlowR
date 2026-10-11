import SwiftUI

/// A symbol in a softly tinted rounded square: a row's or a tile's icon.
/// Forest green (the brand), or a status's colours when the row is about
/// one (`PlowRColor.Status`: owed, overdue…). The client page's quick
/// actions use the same look at 48 points.
struct IconBadge: View {
    let systemImage: String
    var status: PlowRColor.Status?
    var size: CGFloat = 40

    var body: some View {
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
