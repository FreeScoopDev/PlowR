import SwiftUI

// MARK: - 1.7 design (Evergreen & Copper)

/// A screen's one main action in the 1.7 design: copper, full width, at
/// least glove height, Barlow label. Greys itself when disabled.
struct PlowRActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PlowRFont.button)
            .foregroundStyle(isEnabled ? PlowRColor.onAction : PlowRColor.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: PlowRLayout.gloveTapTarget)
            .padding(.horizontal, PlowRLayout.space4)
            .background(isEnabled ? PlowRColor.action : PlowRColor.raised,
                        in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
    }
}

/// A secondary action beside or above the main one: raised fill, ink text,
/// full width, at least the minimum tap height.
struct PlowRSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? PlowRColor.ink : PlowRColor.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: PlowRLayout.secondaryTapTarget)
            .padding(.horizontal, PlowRLayout.space3)
            .background(PlowRColor.raised, in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.6))
            .contentShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
    }
}

extension ButtonStyle where Self == PlowRActionButtonStyle {
    static var plowRAction: PlowRActionButtonStyle { PlowRActionButtonStyle() }
}

extension ButtonStyle where Self == PlowRSecondaryButtonStyle {
    static var plowRSecondary: PlowRSecondaryButtonStyle { PlowRSecondaryButtonStyle() }
}
