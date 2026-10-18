import SwiftUI

extension View {
    /// While `hasChanges`, Back asks first: Save (when `canSave`) or Discard
    /// Changes, and tapping outside keeps editing; `message` says what isn't
    /// saved, and `cantSaveMessage` why it can't be when it can't. The system Back button, and its swipe, give way to one that
    /// asks; while `isBusy` (a save underway) neither shows. Edit Client used
    /// to drop every edit on Back without a word.
    func asksBeforeLeaving(hasChanges: Bool, isBusy: Bool, canSave: Bool, message: String,
                           cantSaveMessage: String,
                           save: @escaping () -> Void, discard: @escaping () -> Void) -> some View {
        modifier(UnsavedChangesGuard(hasChanges: hasChanges, isBusy: isBusy, canSave: canSave,
                                     message: message, cantSaveMessage: cantSaveMessage,
                                     save: save, discard: discard))
    }
}

private struct UnsavedChangesGuard: ViewModifier {
    let hasChanges: Bool
    let isBusy: Bool
    let canSave: Bool
    let message: String
    let cantSaveMessage: String
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
            .confirmationDialog(canSave ? "Save your changes?" : "Discard your changes?",
                                isPresented: $asking, titleVisibility: .visible) {
                if canSave {
                    Button("Save") { save() }
                }
                Button("Discard Changes", role: .destructive) { discard() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text(canSave ? message : cantSaveMessage)
            }
    }
}
