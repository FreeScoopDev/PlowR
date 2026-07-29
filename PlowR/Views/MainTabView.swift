import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Query private var allProposals: [Proposal]

    private var documentsBadge: Int {
        allProposals.filter {
            $0.operatorID == authManager.userID &&
            ($0.invoiceStatus == .draft || $0.invoiceStatus == .overdue)
        }.count
    }

    var body: some View {
        TabView {
            NavigationStack { ClientListView() }
                .tabItem { Label("Clients", systemImage: "person.2.fill") }

            NavigationStack { RouteListView() }
                .tabItem { Label("Routes", systemImage: "map.fill") }

            NavigationStack { ProposalListView() }
                .tabItem { Label("Documents", systemImage: "doc.stack.fill") }
                .badge(documentsBadge > 0 ? documentsBadge : 0)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
}
