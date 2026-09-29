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
            switch PlowRLink(url) {
            case .activeRoute:
                selectedTab = 2
            case .completeStop(let stopID):
                // Control Center's Complete Stop, for the stop its widget
                // showed. The route screen, up while a route is in progress,
                // shows the next stop, or why this one wasn't completed.
                RouteSessionManager.shared.completeStopMessage =
                    CompleteStopAction.controlCenter(stopID: stopID, in: .shared, role: userRole)
            case nil:
                break
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
}
