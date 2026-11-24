import SwiftUI

/// "<What was done> · Undo": the brand capsule the route screen shows after
/// Complete Stop, and the Undo toast (`undoToast()`) shows after Delete, Skip
/// and Complete elsewhere. One look for both.
struct UndoBar: View {
    var title: String
    var systemImage: String
    /// The Undo button's VoiceOver label, e.g. "Undo completing Pat".
    var accessibilityLabel: String
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Large text: the words above the button, so the name has the full width.
        let barLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: PlowRLayout.space3))
        barLayout {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PlowRColor.onBrand)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, typeSize.isAccessibilitySize ? PlowRLayout.space3 : 0)
            Button(action: action) {
                Text("Undo")
                    .font(PlowRFont.button)
                    .foregroundStyle(PlowRColor.onBrand)
                    .padding(.horizontal, PlowRLayout.space4)
                    .frame(minWidth: PlowRLayout.gloveTapTarget, minHeight: PlowRLayout.gloveTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
        }
        .padding(.leading, PlowRLayout.space4)
        .padding(.trailing, PlowRLayout.space1)
        .background(PlowRColor.brand, in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        .padding(.horizontal, PlowRLayout.space4)
        .padding(.top, PlowRLayout.space2)
        .padding(.bottom, PlowRLayout.space2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Shows `UndoCenter`'s offer while it lives, under the screen's content
/// (a bottom safe-area inset: above the tab bar, and the content scrolls
/// clear of it, so it never covers the screen's own actions).
private struct UndoToast: ViewModifier {
    @Environment(UndoCenter.self) private var center

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let offer = center.offer {
                    UndoBar(title: offer.title, systemImage: offer.systemImage,
                            accessibilityLabel: offer.accessibilityLabel) { undo(offer) }
                        .id(offer.id)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: center.offer)
    }

    /// Refused, the toast just closes, with a warning and a word for VoiceOver,
    /// as the route screen's does.
    private func undo(_ offer: UndoCenter.Offer) {
        let refusal: String
        switch center.undo(offer.id) {
        case .undone:
            Haptics.success()
            return
        case .expired: refusal = "Too late to undo."
        case .changed: refusal = "Can't undo: it was changed since."
        case .nothingToUndo: refusal = "Nothing to undo."
        }
        Haptics.warning()
        AccessibilityNotification.Announcement(refusal).post()
    }
}

extension View {
    /// The Undo toast for the app's tabs (MainTabView), and any sheet that
    /// does an undoable action.
    func undoToast() -> some View {
        modifier(UndoToast())
    }
}
