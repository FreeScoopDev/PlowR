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

    // Readable by DashboardView to show a sync-unavailable warning banner.
    static private(set) var isCloudKitAvailable = true

    // True when the process is running under XCTest. Unit tests inject into the
    // host app, so XCTestConfigurationFilePath is set in the environment.
    //
    // CloudKit mirroring is skipped in that case, and it is not optional. The
    // `try?` below cannot protect against a CloudKit failure: CoreData accepts
    // the configuration, then sets CloudKit up asynchronously on
    // com.apple.coredata.cloudkit.queue and TRAPS rather than throwing. No
    // `catch` can reach that. CI runners are signed out of iCloud and build with
    // CODE_SIGNING_ALLOWED=NO, so they carry no iCloud entitlement at all — the
    // host app dies a few seconds after launch, which surfaces as
    // "Test crashed with signal trap before establishing connection."
    //
    // Tests have no business syncing to a real iCloud database regardless.
    // Same guard, same reason, as Wockett's AppModelContainer.
    static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private static func makeContainer(schema: Schema) -> ModelContainer {
        // 1. Try CloudKit-backed store (skipped under test — see above)
        if !isRunningUnderTests {
            let cloudConfig = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.com.Scoops.PlowR")
            )
            if let c = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                isCloudKitAvailable = true
                return c
            }
        }

        // 2. Fall back to local store (iCloud unavailable or signed out)
        isCloudKitAvailable = false
        if let c = try? ModelContainer(for: schema) {
            return c
        }

        // 3. Store is incompatible — archive it with a timestamp instead of deleting,
        //    so data can be manually recovered if needed.
        let support = URL.applicationSupportDirectory
        let stamp = Int(Date().timeIntervalSince1970)
        for file in ["default.store", "default.store-wal", "default.store-shm"] {
            let src = support.appending(path: file)
            let dst = support.appending(path: "\(file).\(stamp).bak")
            try? FileManager.default.moveItem(at: src, to: dst)
        }

        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer after archiving stale store: \(error)")
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
