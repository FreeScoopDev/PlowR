import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(CalendarSync.self) private var calendarSync
    @AppStorage(UserRole.key) private var userRole = ""
    @State private var selectedTab = 0
    @AppStorage(DeviceSync.removeKey) private var removalPending = false

    var body: some View {
        Group {
            if removalPending {
                // Remove from This Device finishes when PlowR next opens: the
                // database can't be removed while it's open.
                RemovedFromDeviceView()
            } else if userRole.isEmpty {
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

/// After Remove from This Device, until PlowR is opened again.
struct RemovedFromDeviceView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Removed from This Device", systemImage: "iphone.slash")
        } description: {
            Text("To finish, close PlowR: swipe up from the bottom of the screen, then swipe PlowR away. When it opens again, its data is gone from this device. It's still in your iCloud and on your other devices, and iCloud sync stays off here until you turn it on in Settings.")
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
        .environment(CalendarSync.shared)
}
