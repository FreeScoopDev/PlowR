import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(ActiveRouteStore.self) private var activeRoute
    @Environment(CalendarSync.self) private var calendarSync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.access) private var access
    @State private var gate: ProGate?
    @State private var showingPaywall = false
    @State private var showingManage = false
    @State private var restoreFailed = false

    @State private var showingFindService = false
    /// The request screen at the end of Find Services requires this store.
    /// Client mode provides one; this entry point didn't, which crashed on Send.
    @State private var workOrderStore = ClientWorkOrderStore()
    @State private var sampleDataInserted = false
    @State private var schemaStatus: String?
    @State private var showingDeleteConfirmation = false
    /// Export My Data First, from the Delete Account & Data dialog.
    @State private var showingExportFirst = false
    /// iCloud sync on this device (DeviceSync): off only by Remove from This
    /// Device; turned back on here, from the next launch.
    @AppStorage(DeviceSync.offKey) private var syncOffHere = false
    /// What Delete Account & Data couldn't remove, shown under the button.
    @State private var deleteFailures: [AccountEraser.Failure] = []
    private let iCloud = ICloudStatus.shared

    private var iCloudSymbol: String {
        switch iCloud.summary.kind {
        case .backedUp: return "icloud.fill"
        case .unknown: return "icloud"
        case .problem: return "icloud.slash"
        }
    }

    private var iCloudTint: Color {
        switch iCloud.summary.kind {
        case .backedUp: return .blue
        case .unknown: return .secondary
        case .problem: return .orange
        }
    }

    var body: some View {
        Form {
            ProSettingsSection(showingPaywall: $showingPaywall, showingManage: $showingManage,
                               restoreFailed: $restoreFailed)

            Section("Business") {
                NavigationLink(destination: BusinessProfileView()) {
                    Label("Business Profile", systemImage: "building.2")
                }
                NavigationLink(destination: ServiceCatalogView()) {
                    Label("Service Catalog", systemImage: "list.bullet.clipboard")
                }
                NavigationLink(destination: PaymentMethodsView()) {
                    Label("Payment Methods", systemImage: "creditcard")
                }
                if let blocked = ProGate.proFeature("The Request Link", access) {
                    Button { gate = blocked } label: {
                        Label("Request Link", systemImage: "link")
                    }
                    .foregroundStyle(.primary)
                } else {
                    NavigationLink(destination: RequestLinkView()) {
                        Label("Request Link", systemImage: "link")
                    }
                }
                // A Pro tool: without Pro, the row says why instead of opening.
                if let blocked = ProGate.proFeature("Import Clients", access) {
                    Button { gate = blocked } label: {
                        Label("Import Clients", systemImage: "square.and.arrow.down.on.square")
                    }
                    .foregroundStyle(.primary)
                } else {
                    NavigationLink(destination: ImportClientsView()) {
                        Label("Import Clients", systemImage: "square.and.arrow.down.on.square")
                    }
                }
                NavigationLink(destination: ExportDataView()) {
                    Label("Export Data", systemImage: "square.and.arrow.up.on.square")
                }
            }

            Section {
                Toggle(isOn: Binding(get: { calendarSync.isEnabled || calendarSync.isAsking },
                                     set: { on in Task { await calendarSync.setEnabled(on) } })) {
                    Label("Add Visits to Calendar", systemImage: "calendar")
                }
            } header: {
                Text("Calendar")
            } footer: {
                calendarFooter
            }

            Section("Discover") {
                Button {
                    showingFindService = true
                } label: {
                    Label("Find Services Near Me", systemImage: "location.magnifyingglass")
                }
            }

            Section {
                // It said "Backed Up" whatever iCloud's state (ICloudStatus).
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iCloudSymbol)
                        .font(.title2)
                        .foregroundStyle(iCloudTint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(iCloud.summary.title)
                            .font(.subheadline.weight(.semibold))
                        Text(iCloud.summary.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if PlowRApp.isSyncTurnedOff {
                    if syncOffHere {
                        Button("Turn iCloud Sync Back On") { DeviceSync.turnOn() }
                    } else {
                        Text("Close PlowR and open it again to sync. Your iCloud data comes back to this device, and anything added here while sync was off goes to iCloud.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Button {
                    if let url = URL(string: "mailto:support@getplowr.app?subject=PlowR%20Support") {
                        openURL(url)
                    }
                } label: {
                    Label("Contact Support", systemImage: "envelope")
                }
            } header: {
                Text("Data & Backup")
            } footer: {
                Text("Your data syncs through your private iCloud to every device signed in to your Apple ID. To take PlowR's data off one device and leave the others alone, use Delete Account & Data → Remove from This Device: that also turns sync off on that device until you turn it back on here. Export Data (under Business) keeps a copy as spreadsheets.")
                    .font(.caption)
            }

            if OnMac.isMac {
                Section {
                    ForEach(OnMac.limitations, id: \.self) { line in
                        Text(line).font(.subheadline)
                    }
                } header: {
                    Text("On a Mac")
                }
            }

            Section("Account") {
                if !authManager.operatorName.isEmpty {
                    LabeledContent("Name", value: authManager.operatorName)
                }
                LabeledContent("Account", value: "Apple ID")
            }

            Section {
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Text("Sign Out")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete Account & Data")
                }
            } footer: {
                if !deleteFailures.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not everything was deleted. Left: \(deleteFailures.map(\.step).joined(separator: ", ")). You're still signed in, so you can try again.")
                        // Only the user can fix this one, so say how.
                        if let calendar = deleteFailures.first(where: { $0.step == AccountEraser.calendarStep }) {
                            Text(calendar.reason)
                        }
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("Legal") {
                if let url = URL(string: "https://getplowr.app/privacy-policy.html") {
                    Link("Privacy Policy", destination: url)
                }
                if let url = URL(string: "https://getplowr.app/terms-of-service.html") {
                    Link("Terms of Service", destination: url)
                }
            }

            #if DEBUG
            Section {
                Button {
                    insertSampleData()
                } label: {
                    Label(
                        sampleDataInserted ? "Sample Data Added" : "Populate Sample Clients",
                        systemImage: sampleDataInserted ? "checkmark.circle.fill" : "person.badge.plus"
                    )
                }
                .disabled(sampleDataInserted)
                Button {
                    setUpSchema()
                } label: {
                    Label(schemaStatus ?? "Set Up iCloud Schema", systemImage: "icloud.and.arrow.up")
                }
                .disabled(schemaStatus == "Setting Up…")
            } header: {
                Text("Developer")
            } footer: {
                Text("Populate adds sample Claremont, NH clients for testing. Set Up iCloud Schema puts every record type and field into iCloud's Development database, to deploy to Production before a release (CloudKitSchemaSetup).")
            }
            #endif
        }
        .navigationTitle("Settings")
        .proGateSheet($gate)
        // PlowR Pro's sheets, here on the Form, never on its section.
        .modifier(ProSettingsSection.Presentations(showingPaywall: $showingPaywall, showingManage: $showingManage,
                                                   restoreFailed: $restoreFailed))
        .sheet(isPresented: $showingFindService) {
            FindServiceFlow()
                .environment(workOrderStore)
        }
        .navigationDestination(isPresented: $showingExportFirst) { ExportDataView() }
        .confirmationDialog("Delete Account & Data", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Export My Data First") { showingExportFirst = true }
            Button("Remove from This Device", role: .destructive, action: removeFromThisDevice)
            // With sync off it couldn't reach iCloud (DeviceSync).
            if !PlowRApp.isSyncTurnedOff {
                Button("Delete Everything", role: .destructive, action: deleteAccount)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(PlowRApp.isSyncTurnedOff
                 ? "Export My Data First saves your clients, proposals, invoices, payments, contracts, schedule and Service History as spreadsheets, a copy to keep: they can't be loaded back into PlowR, and routes, photos and settings aren't in them (share photos from each client's Photos page).\n\niCloud sync is off on this device, so Remove from This Device is the only way to delete here: it permanently removes what's on this device, which isn't in iCloud. To delete your iCloud data, turn sync back on above, reopen PlowR, then choose Delete Everything, or do it from another device." + Self.subscriptionNoteOne
                 : "Export My Data First saves your clients, proposals, invoices, payments, contracts, schedule and Service History as spreadsheets, a copy to keep: they can't be loaded back into PlowR, and routes, photos and settings aren't in them (share photos from each client's Photos page).\n\nRemove from This Device takes PlowR's data off this device only and turns iCloud sync off here; your iCloud and your other devices keep it. Anything this device hasn't sent to iCloud yet is lost, so be online and give it a minute first.\n\nDelete Everything permanently removes all your PlowR data: clients, routes, jobs, documents, contracts, photos and settings, from this device and from your iCloud, so also from your other devices. Stay online with PlowR open for a minute afterwards so iCloud gets the deletion." + Self.subscriptionNote)
        }
    }

    /// Deleting data leaves an App Store subscription running (App Review
    /// checks this is said).
    static let subscriptionNote = "\n\nNeither cancels a PlowR Pro subscription: Apple keeps billing it until you cancel it in PlowR Pro → Manage Subscription, above."
    static let subscriptionNoteOne = "\n\nRemoving your data doesn't cancel a PlowR Pro subscription: Apple keeps billing it until you cancel it in PlowR Pro → Manage Subscription, above."

    @ViewBuilder private var calendarFooter: some View {
        if calendarSync.needsAccess {
            VStack(alignment: .leading, spacing: 6) {
                Text("PlowR needs full access to your calendars to keep its events in step with your visits.")
                Button("Allow in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.caption.weight(.semibold))
            }
        } else if let problem = calendarSync.problem {
            Text(problem)
                .foregroundStyle(.red)
        } else {
            Text("Adds your visits from the last month and the next six months to a “PlowR” calendar, with a reminder an hour before, and keeps it up to date when visits are moved, skipped or deleted. The switch is for this device; in iCloud, the calendar shows on your other devices too.")
        }
    }

    /// Remove from This Device: nothing in iCloud is touched (AccountEraser,
    /// DeviceSync). Finished at the next launch.
    private func removeFromThisDevice() {
        let eraser = AccountEraser(context: modelContext,
                                   archiveFolders: AccountEraser.archiveFolders(for: modelContext.container),
                                   routeStore: activeRoute)
        deleteFailures = eraser.removeFromThisDevice(thenSignOut: authManager.signOut)
    }

    private func deleteAccount() {
        // Everything on this device: records, preferences, files, notifications,
        // geofences, the route in progress, the widget and the PlowR calendar
        // (see AccountEraser).
        let eraser = AccountEraser(context: modelContext,
                                   archiveFolders: AccountEraser.archiveFolders(for: modelContext.container),
                                   routeStore: activeRoute)
        // Signed out only once everything is gone, so what's left can be retried.
        deleteFailures = eraser.eraseAll(thenSignOut: authManager.signOut)
    }

    #if DEBUG
    private func setUpSchema() {
        schemaStatus = "Setting Up…"
        Task { @MainActor in
            await Task.yield()
            do {
                try CloudKitSchemaSetup.run()
                schemaStatus = "Schema Set Up"
            } catch {
                schemaStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func insertSampleData() {
        let operatorID = authManager.userID
        let clients: [(name: String, phone: String, address: String, lat: Double, lon: Double)] = [
            ("Tom Belanger", "603-542-1234", "14 Maple St, Claremont, NH 03743", 43.3770, -72.3451),
            ("Sandra Pierce", "603-542-5678", "88 Washington St, Claremont, NH 03743", 43.3742, -72.3478),
            ("Ray Doucette", "603-542-8901", "7 Elm St, Claremont, NH 03743", 43.3756, -72.3462),
            ("Linda Fortier", "603-543-2345", "231 Pleasant St, Claremont, NH 03743", 43.3782, -72.3435),
            ("Mike Gagnon", "603-543-6789", "55 Church St, Claremont, NH 03743", 43.3761, -72.3489),
        ]
        for c in clients {
            let client = Client(name: c.name, phone: c.phone, address: c.address, operatorID: operatorID)
            client.latitude = c.lat
            client.longitude = c.lon
            modelContext.insert(client)
        }
        sampleDataInserted = true
    }
    #endif
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
        .environment(CalendarSync.shared)
}
