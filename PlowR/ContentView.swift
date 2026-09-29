import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(CalendarSync.self) private var calendarSync
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
        // Only the signed-in business's visits go in the calendar.
        .onChange(of: authManager.userID, initial: true) { _, userID in
            calendarSync.operatorID = userID
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
        .environment(CalendarSync.shared)
}
