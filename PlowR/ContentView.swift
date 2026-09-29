import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("userRole") private var userRole = ""
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if userRole.isEmpty {
                RoleSelectionView()
            } else if userRole == "client" {
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
            guard url.scheme == "plowr" else { return }
            if url.host == "activeRoute" {
                selectedTab = 2
            }
            // Control Center's Complete Stop. The route screen, shown while a
            // route is in progress, then shows the next stop.
            if url.host == "completeStop" {
                _ = CompleteStopAction.run(in: .shared)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
}
