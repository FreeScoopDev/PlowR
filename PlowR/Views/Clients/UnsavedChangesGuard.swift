import SwiftUI

extension View {
    /// While `hasChanges`, Back asks first: Save or Discard Changes (tapping
    /// outside keeps editing). The system Back button, and its swipe, give
    /// way to one that asks; while `isBusy` (a save underway) neither shows.
    /// Edit Client used to drop every edit on Back without a word.
    func asksBeforeLeaving(hasChanges: Bool, isBusy: Bool,
                           save: @escaping () -> Void, discard: @escaping () -> Void) -> some View {
        modifier(UnsavedChangesGuard(hasChanges: hasChanges, isBusy: isBusy, save: save, discard: discard))
    }
}

private struct UnsavedChangesGuard: ViewModifier {
    let hasChanges: Bool
    let isBusy: Bool
    let save: () -> Void
    let discard: () -> Void
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(isBusy || hasChanges)
            .toolbar {
                if hasChanges && !isBusy {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { asking = true } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .tint(.primary)                    // as the system's Back is
                        .accessibilityLabel("Back")
                    }
                }
            }
            .confirmationDialog("Save your changes?", isPresented: $asking, titleVisibility: .visible) {
                Button("Save") { save() }
                Button("Discard Changes", role: .destructive) { discard() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your changes to this client haven't been saved.")
            }
    }
}
