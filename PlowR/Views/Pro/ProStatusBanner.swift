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
        // The Dashboard's card (surface, hairline) and type, like the iCloud
        // note above it: this was the system's grouped grey with larger text.
        PlowRCard {
            HStack(alignment: .top, spacing: PlowRLayout.space3) {
                IconBadge(systemImage: icon, size: 36)
                VStack(alignment: .leading, spacing: PlowRLayout.space1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlowRColor.ink)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(PlowRColor.inkSecondary)
                    Button(closable ? "See PlowR Pro" : "Subscribe Again") { showingPaywall = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PlowRColor.brand)
                        .padding(.top, PlowRLayout.space1)
                }
                Spacer(minLength: 0)
                if closable {
                    Button {
                        closed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PlowRColor.inkSecondary)
                            // A small mark, a full-size target.
                            .frame(minWidth: PlowRLayout.minTapTarget, minHeight: PlowRLayout.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(PlowRLayout.space3)
        }
    }
}
