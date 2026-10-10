import SwiftData
import SwiftUI

/// Works out PlowR Pro's `access` for everything below it, live: from the
/// subscription and this business's clients, so a purchase or a new client
/// changes it at once. `MainTabView` uses it, and so does any screen hosted
/// outside it (`LeadRequestWindow`).
private struct AccessProvider: ViewModifier {
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]
    private let subscription = Subscription.shared

    func body(content: Content) -> some View {
        content.environment(\.access, Access(plan: subscription.plan, clients: allClients,
                                              operatorID: authManager.userID))
    }
}

extension View {
    /// PlowR Pro's `access` for this view and everything below it. Needs
    /// `AuthManager` and a model container above it.
    func providesAccess() -> some View {
        modifier(AccessProvider())
    }
}
