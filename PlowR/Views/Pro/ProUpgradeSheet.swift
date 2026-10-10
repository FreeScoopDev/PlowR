import SwiftUI

/// Says why an action needs PlowR Pro, and opens the subscribe screen.
struct ProUpgradeSheet: View {
    let gate: ProGate
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: gate == .readOnly ? "lock.shield.fill" : "star.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(PlowRColor.accent)
                    .accessibilityHidden(true)
                Text(gate.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(gate.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showingPaywall = true
                } label: {
                    Text(gate == .readOnly ? "Subscribe Again" : "See PlowR Pro")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .center)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingPaywall, onDismiss: closeIfSubscribed, content: { ProPaywallView() })
    }

    /// Subscribed: nothing left to say here.
    private func closeIfSubscribed() {
        if Subscription.shared.plan == .pro { dismiss() }
    }
}

extension View {
    /// The upgrade sheet, shown whenever a check returns a gate.
    func proGateSheet(_ gate: Binding<ProGate?>) -> some View {
        sheet(item: gate) { ProUpgradeSheet(gate: $0) }
    }
}

extension Binding where Value == ProGate? {
    /// Runs `action`, or shows why it needs PlowR Pro:
    /// `$gate.unless(ProGate.addClient(access)) { showingAdd = true }`.
    func unless(_ blocked: ProGate?, _ action: () -> Void) {
        if let blocked { wrappedValue = blocked } else { action() }
    }
}
