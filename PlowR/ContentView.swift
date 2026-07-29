import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("userRole") private var userRole = ""

    var body: some View {
        Group {
            if userRole.isEmpty {
                RoleSelectionView()
            } else if userRole == "client" {
                ClientHomeView()
            } else {
                if authManager.isSignedIn {
                    MainTabView()
                } else {
                    SignInView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
}
