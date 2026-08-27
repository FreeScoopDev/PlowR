import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var showingFindService = false
    @State private var sampleDataInserted = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
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
            }

            Section("Discover") {
                Button {
                    showingFindService = true
                } label: {
                    Label("Find Services Near Me", systemImage: "location.magnifyingglass")
                }
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "icloud.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data Backed Up to iCloud")
                            .font(.subheadline.weight(.semibold))
                        Text("Your clients, routes, and documents sync automatically across your devices and are stored securely in your private iCloud account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

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
                Text("Need a manual export or have questions about your data?")
                    .font(.caption)
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
            }

            Section("Legal") {
                Link("Privacy Policy", destination: URL(string: "https://getplowr.app/privacy-policy.html")!)
                Link("Terms of Service", destination: URL(string: "https://getplowr.app/terms-of-service.html")!)
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
            } header: {
                Text("Developer")
            } footer: {
                Text("Adds sample Claremont, NH clients for testing.")
            }
            #endif
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingFindService) {
            FindServiceFlow()
        }
        .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Delete Everything", role: .destructive, action: deleteAccount)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all clients, routes, proposals, and settings from this device. To also remove your iCloud data, go to Settings → [your name] → iCloud → Manage Account Storage → PlowR after signing out.")
        }
    }

    private func deleteAccount() {
        try? modelContext.delete(model: StopPhoto.self)
        try? modelContext.delete(model: RouteStop.self)
        try? modelContext.delete(model: PropertyZone.self)
        try? modelContext.delete(model: PlowRoute.self)
        try? modelContext.delete(model: ProposalLineItem.self)
        try? modelContext.delete(model: Proposal.self)
        try? modelContext.delete(model: ScheduledVisit.self)
        try? modelContext.delete(model: ServiceItem.self)
        try? modelContext.delete(model: PaymentMethod.self)
        try? modelContext.delete(model: Client.self)
        try? modelContext.delete(model: BusinessProfile.self)
        try? FileManager.default.removeItem(at: ClientWorkOrderStore.fileURL)
        authManager.signOut()
    }

    #if DEBUG
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
}
