import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ActiveRouteStore.self) private var activeRoute
    @Query private var allProposals: [Proposal]
    @Binding var selectedTab: Int
    /// Home's "+ N more" asks the Schedule to show today.
    @State private var scheduleTodayRequests = 0

    private var documentsBadge: Int {
        DocumentsBadge.count(allProposals, operatorID: authManager.userID)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(openTodayInSchedule: {
                scheduleTodayRequests += 1
                selectedTab = 4
            })
                .tabItem { Label("Home", systemImage: PlowRSymbol.home.name) }
                .tag(0)

            NavigationStack { ClientListView() }
                .tabItem { Label("Clients", systemImage: PlowRSymbol.client.name) }
                .tag(1)

            NavigationStack { RouteListView() }
                .tabItem { Label("Routes", systemImage: PlowRSymbol.route.name) }
                .tag(2)

            NavigationStack { ProposalListView() }
                .tabItem { Label("Documents", systemImage: PlowRSymbol.document.name) }
                .badge(documentsBadge > 0 ? documentsBadge : 0)
                .tag(3)

            ScheduleView(todayRequests: scheduleTodayRequests)
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

/// The Documents tab's badge: what needs action now. Overdue invoices only;
/// a draft is the user's own work in progress, not something waiting on them,
/// and counting drafts kept the badge lit all the time.
enum DocumentsBadge {
    static func count(_ proposals: [Proposal], operatorID: String, now: Date = Date()) -> Int {
        proposals.filter {
            $0.operatorID == operatorID && $0.invoiceStatus(now: now) == .overdue
        }.count
    }
}

#Preview {
    MainTabView(selectedTab: .constant(0))
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
}
