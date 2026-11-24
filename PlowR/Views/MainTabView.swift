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
        // Each tab hosts the Undo toast (UndoCenter) under its content, above
        // the tab bar: an offer made on one tab still shows on another (Home
        // hides a pending delete too). Never over the route screen, which
        // covers the tabs.
        TabView(selection: $selectedTab) {
            DashboardView()
                .undoToast()
                .tabItem { Label("Home", systemImage: PlowRSymbol.home.name) }
                .tag(0)

            NavigationStack { ClientListView() }
                .undoToast()
                .tabItem { Label("Clients", systemImage: PlowRSymbol.client.name) }
                .tag(1)

            NavigationStack { RouteListView() }
                .undoToast()
                .tabItem { Label("Routes", systemImage: PlowRSymbol.route.name) }
                .tag(2)

            NavigationStack { ProposalListView() }
                .undoToast()
                .tabItem { Label("Documents", systemImage: PlowRSymbol.document.name) }
                .badge(documentsBadge > 0 ? documentsBadge : 0)
                .tag(3)

            ScheduleView()
                .undoToast()
                .tabItem { Label("Schedule", systemImage: PlowRSymbol.schedule.name) }
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
        // What access says, for the tips' rules; inside providesAccess.
        .feedsTips()
        // PlowR Pro: what this business may do, for every screen below.
        .providesAccess()
    }
}

#Preview {
    MainTabView(selectedTab: .constant(0))
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
        .environment(UndoCenter.shared)
}
