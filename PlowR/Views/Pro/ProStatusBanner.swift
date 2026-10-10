import SwiftUI

/// The Dashboard's line after a subscription ends: read only (it stays), or
/// the free tier (until closed). Nothing for anyone else.
struct ProStatusBanner: View {
    @Environment(\.access) private var access
    /// The free-tier note was closed. Shown again after a later lapse: the
    /// Dashboard clears it on subscribing (`reopenOnSubscribe`), since this
    /// view isn't there to see it while it shows nothing.
    static let closedKey = "freeAfterCancellingClosed"
    @AppStorage(closedKey) private var closed = false
    @State private var showingPaywall = false

    var body: some View {
        Group {
            if access.tier == .readOnly {
                banner(icon: "lock.shield.fill",
                       title: "Your subscription ended",
                       message: ProGate.readOnly.message,
                       closable: false)
            } else if access.isFreeAfterCancelling && !closed {
                banner(icon: "star.circle",
                       title: "You're on the free tier",
                       message: "Your subscription ended, and with \(Access.freeClientLimit) clients or fewer PlowR stays free: up to \(Access.freeClientLimit) clients and one route.",
                       closable: true)
            }
        }
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
    }

    /// For an always-present view to run when the plan changes.
    static func reopenOnSubscribe(_ plan: Access.Plan, defaults: UserDefaults = .standard) {
        if plan == .pro { defaults.set(false, forKey: closedKey) }
    }

    private func banner(icon: String, title: String, message: String, closable: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(PlowRColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Button(closable ? "See PlowR Pro" : "Subscribe Again") { showingPaywall = true }
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
            if closable {
                Button {
                    closed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
