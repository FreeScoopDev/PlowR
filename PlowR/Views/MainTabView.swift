import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ActiveRouteStore.self) private var activeRoute
    @Query private var allProposals: [Proposal]
    @Binding var selectedTab: Int

    private var documentsBadge: Int {
        allProposals.filter {
            $0.operatorID == authManager.userID &&
            ($0.invoiceStatus == .draft || $0.invoiceStatus == .overdue)
        }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { ClientListView() }
                .tabItem { Label("Clients", systemImage: "person.2.fill") }
                .tag(1)

            NavigationStack { RouteListView() }
                .tabItem { Label("Routes", systemImage: "map.fill") }
                .tag(2)

            NavigationStack { ProposalListView() }
                .tabItem { Label("Documents", systemImage: "doc.stack.fill") }
                .badge(documentsBadge > 0 ? documentsBadge : 0)
                .tag(3)

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(4)
        }
        // The route screen is shown from here, the app's root, whenever a route
        // is in progress, so a route restored after a relaunch comes straight
        // back. Only ActiveRouteStore.end() closes it; the setter is a no-op.
        .fullScreenCover(isPresented: Binding(get: { activeRoute.isActive }, set: { _ in })) {
            if let route = activeRoute.route {
                ActiveRouteView(route: route)
            }
        }
        // PlowR Pro: what this business may do, for every screen below.
        .providesAccess()
    }
}

#Preview {
    MainTabView(selectedTab: .constant(0))
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
}
