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
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
