import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(UserRole.key) private var userRole = ""
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if userRole.isEmpty {
                RoleSelectionView()
            } else if userRole == UserRole.client {
                ClientHomeView()
            } else {
                if authManager.isSignedIn {
                    MainTabView(selectedTab: $selectedTab)
                } else {
                    SignInView()
                }
            }
        }
        .onOpenURL { url in
            if PlowRLink(url) == .activeRoute { selectedTab = 2 }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
}
