import CoreData
import SwiftUI
import SwiftData
import UIKit

@main
struct PlowRApp: App {
    @State private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer

    /// Every SwiftData model. The schema is built from this list and Delete
    /// Account & Data deletes every type in it, so a new model can't be left
    /// out of either.
    static let models: [any PersistentModel.Type] = [
        Client.self,
        PlowRoute.self,
        RouteStop.self,
        ServiceItem.self,
        PropertyZone.self,
        BusinessProfile.self,
        Proposal.self,
        Payment.self,
        ProposalLineItem.self,
        PaymentMethod.self,
        StopPhoto.self,
        ScheduledVisit.self,
        ServiceRecord.self,
        Property.self,
        SentText.self,
        Contract.self,
        TriggerCheck.self,
    ]

    init() {
        let schema = Schema(Self.models)
        container = Self.makeContainer(schema: schema)
        // Stops that fell behind their client, before the route in progress
        // is restored from them; then whenever iCloud brings changes. And
        // "Awaiting Response" is for documents sent now: texts set it before.
        // Not under tests, which bring their own store.
        if !Self.isRunningUnderTests {
            ClientStops.updateAll(in: container.mainContext)
            ClientStops.followRemoteChanges(of: container)
            // Parts of a payment recorded on two devices, now together.
            Payments.settleAll(in: container.mainContext)
            // An invoice number two devices both gave out (InvoiceRecords).
            InvoiceRecords.resolveDuplicateNumbers(in: container.mainContext)
            DocumentSent.clearTextStamps(in: container.mainContext)
            ClientRemoval.takeInactiveClientsOffRoutes(in: container.mainContext)
            // The Service Log: the same work recorded on two devices, merged.
            ServiceLog.mergeDuplicates(in: container.mainContext)
            // Visits completed before it existed, copied in after launch, in
            // passes on a context of its own: a long history is a lot of work.
            let container = container
            Task { await ServiceLog.backfillAll(in: container) }
        }
        // Before any view: a Siri or Control Center launch acts on the route
        // without the UI, and a killed app should come back mid-route.
        ActiveRouteStore.shared.configure(context: container.mainContext)
        // PlowR Pro: the plan kept from last time until StoreKit answers.
        Subscription.shared.start()
        // Not under tests: the test host is the app, with the app's
        // preferences, and must leave the simulator's calendar alone.
        if !Self.isRunningUnderTests {
            CalendarSync.shared.configure(context: container.mainContext)
            // Here, not with the route screen: iOS relaunches the app in the
            // background when the crew reaches or leaves a job site, and hands
            // the crossing to the location manager that exists then.
            _ = SiteMonitor.shared
        }
    }

    // Whether the iCloud database opened at launch (ICloudStatus reads it).
    // It opens fine for a user not signed in to iCloud: that's the account's
    // status, which ICloudStatus asks CloudKit for.
    static private(set) var isCloudKitAvailable = true

    /// iCloud sync was turned off on this device (DeviceSync), so the database
    /// opened without it on purpose.
    static private(set) var isSyncTurnedOff = false

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
    static var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static let iCloudContainer = "iCloud.com.Scoops.PlowR"

    /// The store, synced to iCloud. Unnamed like the local one, so both open
    /// the same file: the app-group container on a signed build.
    static func cloudConfiguration(for schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema, cloudKitDatabase: .private(iCloudContainer))
    }

    /// The same store without an explicit iCloud database. Unverified
    /// whether it stays off iCloud on a signed build: SwiftData's default is
    /// `.automatic`, which can pick the entitlements' container.
    static func localConfiguration(for schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema)
    }

    /// The same store with iCloud off, said so: for a device whose sync was
    /// turned off (DeviceSync). Not `localConfiguration`, which may sync.
    static func offlineConfiguration(for schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema, cloudKitDatabase: .none)
    }

    /// The configuration the store opens with when iCloud's didn't, or wasn't
    /// tried: with sync off on this device, every open is said off, the
    /// fallback and the reopen after archiving included, or a new store could
    /// sync iCloud's records into a device that says it doesn't.
    static func fallbackConfiguration(for schema: Schema, syncOff: Bool) -> ModelConfiguration {
        syncOff ? offlineConfiguration(for: schema) : localConfiguration(for: schema)
    }

    private static func makeContainer(schema: Schema) -> ModelContainer {
        var errors: [String] = []
        // 0. Remove from This Device: the local database goes before it opens
        //    (its files, never its records, which iCloud would copy), and with
        //    sync off here it opens without iCloud, so nothing comes back.
        if !isRunningUnderTests {
            DeviceSync.removeDatabaseIfAsked(storeAt: localConfiguration(for: schema).url)
            isSyncTurnedOff = DeviceSync.isOff()
        }
        // 1. Try CloudKit-backed store (skipped under test — see above)
        if !isRunningUnderTests, !isSyncTurnedOff {
            do {
                let c = try ModelContainer(for: schema, configurations: [cloudConfiguration(for: schema)])
                isCloudKitAvailable = true
                return c
            } catch {
                errors.append("iCloud: \(error)")
            }
        }

        // 2. Fall back to local store (iCloud unavailable or signed out), or
        //    open it with sync off here: iCloud said off, every time.
        isCloudKitAvailable = false
        let local = fallbackConfiguration(for: schema, syncOff: isSyncTurnedOff)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            errors.append("local: \(error)")
        }

        // 3. Move the store aside with a timestamp, never delete it, and start a
        //    new one: only when Core Data says it can't be migrated to this model,
        //    even with iCloud off. Anything else (a store that can't be read yet
        //    after a restart, one that matches the model, a full disk) is left in
        //    place and the app stops, so a fixed build still finds the data.
        let verdict = StoreArchive.verdict(storeAt: local.url, model: NSManagedObjectModel.makeManagedObjectModel(for: models))
        guard verdict == .cannotBeMigrated,
              StoreArchive.archive(storeAt: local.url, stamp: Int(Date().timeIntervalSince1970)) else {
            fatalError("Could not open the store (\(verdict)); it was left in place. \(errors)")
        }
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Could not create ModelContainer after archiving stale store: \(error)")
        }
    }

    /// Pins an import hasn't looked up yet (the rest of a long list), for
    /// the business signed in here; nothing while signed out or with this
    /// device's data about to be removed. Runs when the app comes to the
    /// front and when a business signs in (at launch, Apple's sign-in check
    /// answers after the app is in front).
    private func lookUpImportPins() {
        guard !Self.isRunningUnderTests else { return }
        guard authManager.isSignedIn, !authManager.userID.isEmpty,
              UserDefaults.standard.string(forKey: UserRole.key) == UserRole.business,
              !DeviceSync.isRemovalPending() else {
            // Signed out (or not a business): a run for whoever was stops.
            ImportPins.shared.cancelRun()
            return
        }
        let context = container.mainContext, operatorID = authManager.userID
        Task { await ImportPins.shared.run(in: context, operatorID: operatorID) }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(ActiveRouteStore.shared)
                .environment(CalendarSync.shared)
                .tint(PlowRColor.accent)
        }
        .modelContainer(container)
        // Signed in after the app came to the front (the launch check
        // answers later): the rest of a long list carries on then.
        .onChange(of: authManager.userID) { lookUpImportPins() }
        .onChange(of: scenePhase) { _, phase in
            // iCloud may have deleted or reordered the route while the app was away.
            if phase == .active {
                if !Self.isRunningUnderTests {
                    ClientStops.updateAll(in: container.mainContext)
                    Payments.settleAll(in: container.mainContext)
                    // An invoice number two devices both gave out (InvoiceRecords).
                    InvoiceRecords.resolveDuplicateNumbers(in: container.mainContext)
                    lookUpImportPins()
                    // A subscription that ran out while away sends no update.
                    Task { await Subscription.shared.refresh() }
                }
                ActiveRouteStore.shared.validate()
                authManager.recheckIfSignedOut()
                CalendarSync.shared.refresh()
            }
            // Follow-up reminders from what's on file now: on the way in,
            // and on the way out, so what's due while away is right.
            if (phase == .active || phase == .background) && !Self.isRunningUnderTests {
                FollowUpReminders.refresh(operatorID: authManager.userID, in: container.mainContext)
            }
            // The screens leave saving to autosave, which took up to half a
            // minute on a simulator, and a sync waiting for it doesn't run
            // once the app is suspended: add a visit, open Calendar, and it
            // wasn't there. So sync on the way out, from what's in memory.
            if phase == .background {
                CalendarSync.shared.syncNow()
            }
        }
    }
}
