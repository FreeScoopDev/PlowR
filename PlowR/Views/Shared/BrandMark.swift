import SwiftUI

/// PlowR's mark: the app icon's artwork (Evergreen & Copper, 1.7), with the
/// wordmark in Barlow. The role screen and sign-in showed two different
/// system symbols (a map, a truck), neither the icon.
struct BrandMark: View {
    var size: CGFloat = 96
    var tagline: String?

    var body: some View {
        VStack(spacing: PlowRLayout.space3) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
                .accessibilityHidden(true)
            Text("PlowR")
                .font(PlowRFont.barlow(.extraBold, size: 44, relativeTo: .largeTitle))
                .foregroundStyle(PlowRColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let tagline {
                Text(tagline)
                    .font(.subheadline)
                    .foregroundStyle(PlowRColor.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
