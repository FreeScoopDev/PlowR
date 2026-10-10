import SwiftUI

/// The Dashboard's line after a subscription ends: read only (it stays), or
/// the free tier (until closed). Nothing for anyone else.
struct ProStatusBanner: View {
    @Environment(\.access) private var access
    /// The free-tier note was closed. Shown again after a later lapse.
    @AppStorage("freeAfterCancellingClosed") private var closed = false
    @State private var showingPaywall = false

    var body: some View {
        Group {
            if access.tier == .readOnly {
                banner(icon: "lock.shield.fill",
                       title: "Your subscription ended",
                       message: "Your records are safe: see them, export them and record payments. Subscribe again to pick up where you left off.",
                       closable: false)
            } else if access.isFreeAfterCancelling && !closed {
                banner(icon: "star.circle",
                       title: "You're on the free tier",
                       message: "Your subscription ended, and with \(Access.freeClientLimit) clients or fewer PlowR stays free: up to \(Access.freeClientLimit) clients and one route.",
                       closable: true)
            }
        }
        .onChange(of: access.plan) { _, plan in
            if plan == .pro { closed = false }
        }
        .sheet(isPresented: $showingPaywall) { ProPaywallView() }
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
