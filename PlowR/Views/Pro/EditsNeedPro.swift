import SwiftUI

/// Read only (cancelled with more than the free tier's clients), an editor
/// shows why it can't be used instead of its form, wherever it was opened
/// from: one modifier on the editor rather than a gate on every button that
/// opens it. Free and Pro see the editor.
private struct EditsNeedPro: ViewModifier {
    @Environment(\.access) private var access

    func body(content: Content) -> some View {
        if access.canEdit {
            content
        } else {
            ReadOnlyNotice()
        }
    }
}

/// "Your subscription ended": the records are safe, Subscribe Again, Close.
/// No navigation stack of its own, so it works pushed or in a sheet.
struct ReadOnlyNotice: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: 20) {
            ProGateMessage(gate: .readOnly) { showingPaywall = true }
            Button("Close") { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
    }
}

extension View {
    /// An editor: read only, it shows `ReadOnlyNotice` instead.
    func editsNeedPro() -> some View {
        modifier(EditsNeedPro())
    }
}
