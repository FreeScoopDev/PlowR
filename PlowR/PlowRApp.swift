import SwiftUI
import SwiftData
import UIKit

// Adaptive navy: readable in both light and dark mode
private let appAccentColor = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.53, green: 0.70, blue: 1.00, alpha: 1)   // bright blue for dark mode
        : UIColor(red: 0.118, green: 0.227, blue: 0.541, alpha: 1) // deep navy for light mode
})

@main
struct PlowRApp: App {
    @State private var authManager = AuthManager()
    let container: ModelContainer

    init() {
        let schema = Schema([
            Client.self,
            PlowRoute.self,
            RouteStop.self,
            ServiceItem.self,
            PropertyZone.self,
            BusinessProfile.self,
            Proposal.self,
            ProposalLineItem.self,
            PaymentMethod.self,
            StopPhoto.self,
            ScheduledVisit.self,
        ])
        container = Self.makeContainer(schema: schema)
    }

    private static func makeContainer(schema: Schema) -> ModelContainer {
        // 1. Try CloudKit-backed store
        let cloudConfig = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.Scoops.PlowR")
        )
        if let c = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return c
        }

        // 2. Fall back to local store
        if let c = try? ModelContainer(for: schema) {
            return c
        }

        // 3. Schema changed during development — clear stale store and start fresh
        // Recovering from incompatible store — clear stale database and start fresh
        let support = URL.applicationSupportDirectory
        for file in ["default.store", "default.store-wal", "default.store-shm"] {
            try? FileManager.default.removeItem(at: support.appending(path: file))
        }

        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer after cleanup: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .tint(appAccentColor)
        }
        .modelContainer(container)
    }
}
