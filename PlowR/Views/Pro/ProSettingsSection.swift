import StoreKit
import SwiftUI

extension EnvironmentValues {
    /// What this business may do on its plan, worked out once at the root
    /// (`MainTabView`) from the subscription and its clients.
    @Entry var access = Access(plan: .free, clientCount: 0)
}

/// Settings → PlowR Pro: the plan in words, and the ways to subscribe,
/// manage it or restore it.
struct ProSettingsSection: View {
    @Environment(\.access) private var access
    @State private var showingPaywall = false
    @State private var showingManage = false
    @State private var restoring = false
    @State private var restoreFailed = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.title(for: access))
                    .font(.headline)
                Text(Self.message(for: access))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            // The presentations hang off this one row, never the Section: a
            // modifier on a Form section goes to each of its rows, and
            // See PlowR Pro then closed Settings instead of opening the
            // paywall (simulator, 2026-10-10).
            .sheet(isPresented: $showingPaywall) { ProPaywallView() }
            .manageSubscriptionsSheet(isPresented: $showingManage)
            .alert("Couldn't Restore", isPresented: $restoreFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The App Store didn't answer. Check you're online and signed in to the App Store, then try again.")
            }
            if access.tier != .pro {
                Button {
                    showingPaywall = true
                } label: {
                    Label(access.plan == .lapsed ? "Subscribe Again" : "See PlowR Pro", systemImage: "star.fill")
                }
            }
            // Always: a plan read before a purchase synced here can be wrong,
            // and the delete dialog points here.
            Button {
                showingManage = true
            } label: {
                Label("Manage Subscription", systemImage: "creditcard.and.123")
            }
            Button {
                Task { await restore() }
            } label: {
                Label(restoring ? "Restoring…" : "Restore Purchases", systemImage: "arrow.clockwise")
            }
            .disabled(restoring)
        } header: {
            Text("PlowR Pro")
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            restoreFailed = true
        }
        await Subscription.shared.refresh()
    }

    static func title(for access: Access) -> String {
        switch (access.plan, access.tier) {
        case (.pro, _): "PlowR Pro is on"
        case (.free, _): "Free"
        case (.lapsed, .readOnly): "Your subscription ended"
        case (.lapsed, _): "Free since your subscription ended"
        }
    }

    static func message(for access: Access) -> String {
        let limit = Access.freeClientLimit
        switch (access.plan, access.tier) {
        case (.pro, _):
            return "Unlimited clients and routes, and every business tool."
        case (.lapsed, .readOnly):
            return "Your records are all here to see and export, and you can still record payments. Subscribe again to add, report and run routes, right where you left off."
        case (.lapsed, _):
            return "With \(limit) clients or fewer you keep the free tier: \(access.clientCount) of \(limit) clients and one route. Subscribe again for everything, right where you left off."
        case (.free, _) where access.clientCount > limit:
            return "\(access.clientCount) clients: the free tier adds clients up to \(limit), and runs one route. PlowR Pro has unlimited clients and routes and every business tool."
        case (.free, _):
            return "\(access.clientCount) of \(limit) clients and one route. PlowR Pro has unlimited clients and routes and every business tool."
        }
    }
}
