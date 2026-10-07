import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(CalendarSync.self) private var calendarSync
    @Environment(\.modelContext) private var modelContext
    @AppStorage(UserRole.key) private var userRole = ""
    @State private var selectedTab = 0
    @AppStorage(DeviceSync.removeKey) private var removalPending = false
    @State private var incomingLinks = IncomingLinks.shared
    @State private var leadWindow = LeadRequestWindow.shared
    /// The sign-in alert was seen: the link waits quietly for the sign-in.
    @State private var signInAcknowledged = false

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
        .onOpenURL { url in open(url) }
        // A web link (getplowr.app/lead/…) can arrive as a browsing activity.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { open(url) }
        }
        // A request for the business signed in here, or a damaged link,
        // opens in a window of its own over whatever is on screen
        // (LeadRequestWindow); where no business can take it, an alert says so.
        .onChange(of: route, initial: true) { showLeadWindow() }
        // A request that came in while another was open opens once it closes.
        .onChange(of: leadWindow.isShowing) { showLeadWindow() }
        .alert(rootAlert?.title ?? "", isPresented: Binding(get: { rootAlert != nil },
                                                           set: { if !$0 { dismissRootAlert() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rootAlert?.message ?? "")
        }
    }

    /// A link that opened the app: the route in progress, or Add to PlowR
    /// (kept until it can be acted on).
    private func open(_ url: URL) {
        if PlowRLink(url) == .activeRoute {
            selectedTab = 2
        } else if RequestLink.isLeadLink(url) {
            incomingLinks.pending = url
            signInAcknowledged = false
        }
    }

    /// The New Lead screen, or why a link can't be read, when one is due.
    private func showLeadWindow() {
        guard let route, route.opensWindow, !leadWindow.isShowing else { return }
        leadWindow.show(route, container: modelContext.container, authManager: authManager)
    }

    private var route: IncomingLinks.Route? {
        incomingLinks.pending.flatMap {
            IncomingLinks.route(for: $0, role: userRole, isChecking: authManager.isChecking,
                                isSignedIn: authManager.isSignedIn, removalPending: removalPending)
        }
    }

    /// What the root says about a request it can't open here.
    private var rootAlert: (title: String, message: String)? {
        switch route {
        case .signIn where !signInAcknowledged:
            ("Sign In to Add This Request", "This request is for your business's PlowR. Sign in, and it opens.")
        case .notBusiness:
            ("A Request for a Business", "This link adds a service request to the PlowR of the business it was sent to. It can't be added on this device.")
        case .unavailable:
            ("Can't Add Requests Right Now", "PlowR's data is being removed from this device. Open PlowR again to finish, then tap the link again.")
        default:
            nil
        }
    }

    /// OK on the root's alert: the link goes, except one waiting for a
    /// sign-in, which opens once signed in.
    private func dismissRootAlert() {
        switch route {
        case .signIn: signInAcknowledged = true
        case .notBusiness, .unavailable: incomingLinks.pending = nil
        default: break        // waiting on sign-in, or opening: the link stays
        }
    }
}

/// After Remove from This Device, until PlowR is opened again.
struct RemovedFromDeviceView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Removed from This Device", systemImage: "iphone.slash")
        } description: {
            if DeviceSync.removalFailedAtLaunch {
                Text("PlowR couldn't finish removing its data from this device when it opened. Close it and open it again to try once more; if this stays, restart your phone, or contact support@getplowr.app.")
            } else {
                Text("To finish, close PlowR: swipe up from the bottom of the screen, then swipe PlowR away. When it opens again, its data is gone from this device. What had reached iCloud is still there and on your other devices, and iCloud sync stays off here until you turn it back on in Settings.")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
        .environment(CalendarSync.shared)
}
