//
//  AccountEraserTests.swift
//  PlowRTests
//

import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Delete Account & Data must leave nothing behind (App Review 5.1.1(v)).
/// These write every kind of thing PlowR stores and check each is gone. The
/// client-mode contact details, notifications, geofences, PDFs and database
/// archives all used to survive a delete.
@MainActor
struct AccountEraserTests {

    final class FakeNotifications: NotificationClearing {
        var pending = ["overdue_invoices", "weather_alert"]
        var delivered = ["overdue_invoices"]
        func removeAllPendingNotificationRequests() { pending = [] }
        func removeAllDeliveredNotifications() { delivered = [] }
    }

    final class FakeRegions: RegionMonitoring {
        var monitoredRegions: Set<CLRegion> = [
            CLCircularRegion(center: .init(latitude: 43, longitude: -76), radius: 100, identifier: "stop-1"),
            CLCircularRegion(center: .init(latitude: 43.1, longitude: -76.1), radius: 100, identifier: "stop-2"),
        ]
        func stopMonitoring(for region: CLRegion) { monitoredRegions.remove(region) }
    }

    /// Everything a real account has, in throwaway places.
    @MainActor
    final class Account {
        /// Every preference key the app writes, as of this change.
        static let keys = ["clientName", "clientPhone", "clientEmail", "userRole", "completedRoutesCount",
                           "notifyIncludeLocation", "operatorName", ActiveRouteStore.checkpointKey,
                           CalendarSync.enabledKey, CalendarSync.seenKey, CalendarSync.removalOwedKey,
                           EventKitVisitCalendarStore.calendarIDKey]

        let container: ModelContainer
        let context: ModelContext
        let suite: String
        let defaults: UserDefaults
        let folder: URL
        let tmp: URL
        let storeFolder: URL
        let workOrders: URL
        let routeStore: ActiveRouteStore
        let surfaces = FakeRouteSurfaces()
        let notifications = FakeNotifications()
        let regions = FakeRegions()
        var widgetCleared = false
        var calendarErased = false

        init() throws {
            let suite = "AccountEraserTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let folder = FileManager.default.temporaryDirectory.appending(path: suite)
            let container = try ModelContainer(for: Schema(PlowRApp.models),
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                                  cloudKitDatabase: .none))
            self.suite = suite
            self.defaults = defaults
            self.folder = folder
            tmp = folder.appending(path: "tmp")
            storeFolder = folder.appending(path: "store")
            workOrders = folder.appending(path: "clientWorkOrders.json")
            self.container = container
            context = container.mainContext
            routeStore = ActiveRouteStore(defaults: defaults, surfaces: surfaces, now: { Date() })

            // Related records as the app makes them: a client's zone, a route's
            // stop, a proposal's line, each inserted before it's attached.
            let client = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
            let zone = PropertyZone(label: "Front")
            let route = PlowRoute(name: "Tuesday", operatorID: "op")
            let stop = RouteStop(order: 0, client: client)
            let proposal = Proposal(operatorID: "op", client: client)
            let line = ProposalLineItem(serviceName: "Mowing", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 40)
            let related: [any PersistentModel] = [client, zone, route, stop, proposal, line]
            related.forEach { context.insert($0) }
            zone.client = client
            stop.route = route
            proposal.lineItems = [line]
            let others: [any PersistentModel] = [
                ServiceItem(name: "Mowing", category: "Lawn", unitType: "flat", pricePerUnit: 40, operatorID: "op"),
                BusinessProfile(operatorID: "op"),
                PaymentMethod(operatorID: "op", label: "Venmo", value: "@pat", methodType: "venmo"),
                StopPhoto(operatorID: "op", clientID: client.id.uuidString, routeID: route.id.uuidString,
                          isBefore: true, imageData: Data([1, 2, 3])),
                ScheduledVisit(operatorID: "op", clientID: client.id.uuidString, clientName: client.name,
                               clientAddress: client.address, scheduledDate: Date()),
            ]
            others.forEach { context.insert($0) }
            try context.save()
            routeStore.configure(context: context)
            routeStore.start(route)

            for key in Self.keys where defaults.object(forKey: key) == nil { defaults.set("x", forKey: key) }
            for dir in [tmp, storeFolder] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            for name in ["INV-0001.pdf", "PlowR_Season_Report.pdf"] {
                try Data("%PDF".utf8).write(to: tmp.appending(path: name))
            }
            try Data("keep".utf8).write(to: tmp.appending(path: "notes.txt"))
            for name in ["default.store.1790000000.bak", "default.store-wal.1790000000.bak", "default.store", "other.bak"] {
                try Data([0]).write(to: storeFolder.appending(path: name))
            }
            // An archived photo folder, and the live one, which must stay.
            for folder in [".default_SUPPORT.1790000000.bak/_EXTERNAL_DATA", ".default_SUPPORT/_EXTERNAL_DATA"] {
                let dir = storeFolder.appending(path: folder)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data([9]).write(to: dir.appending(path: "photo"))
            }
            try Data("[]".utf8).write(to: workOrders)
        }

        func eraser() -> AccountEraser {
            AccountEraser(context: context, defaults: defaults, defaultsDomain: suite, workOrdersFile: workOrders,
                          temporaryDirectory: tmp, archiveFolders: [storeFolder], notifications: notifications,
                          regions: regions, routeStore: routeStore, clearWidget: { [unowned self] in widgetCleared = true },
                          eraseCalendar: { [unowned self] in calendarErased = true })
        }

        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        func removeFiles() {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func count<T: PersistentModel>(_ model: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    @Test func everyModelIsDeleted() throws {
        let account = try Account()
        defer { account.removeFiles() }
        for model in PlowRApp.models { #expect(try count(model, in: account.context) > 0, "\(model) not set up") }
        #expect(account.eraser().eraseAll().isEmpty)
        for model in PlowRApp.models { #expect(try count(model, in: account.context) == 0, "\(model)") }
        // Saved, not waiting for autosave: a fresh context sees them gone too.
        let fresh = ModelContext(account.container)
        for model in PlowRApp.models { #expect(try count(model, in: fresh) == 0, "\(model) unsaved") }
    }

    // The client-mode name, phone and email were left in plain preferences.
    @Test func everyPreferenceIsRemoved() throws {
        let account = try Account()
        defer { account.removeFiles() }
        #expect(account.eraser().eraseAll().isEmpty)
        for key in Account.keys { #expect(account.defaults.object(forKey: key) == nil, "\(key)") }
    }

    @Test func filesAreRemovedButTheLiveStoreIsNot() throws {
        let account = try Account()
        defer { account.removeFiles() }
        #expect(account.eraser().eraseAll().isEmpty)
        #expect(!account.exists(account.workOrders))
        #expect(!account.exists(account.tmp.appending(path: "INV-0001.pdf")))
        #expect(!account.exists(account.tmp.appending(path: "PlowR_Season_Report.pdf")))
        #expect(!account.exists(account.storeFolder.appending(path: "default.store.1790000000.bak")))
        #expect(!account.exists(account.storeFolder.appending(path: "default.store-wal.1790000000.bak")))
        #expect(!account.exists(account.storeFolder.appending(path: ".default_SUPPORT.1790000000.bak")))
        #expect(account.exists(account.storeFolder.appending(path: ".default_SUPPORT/_EXTERNAL_DATA/photo")))
        // Only PlowR's own leftovers go: the live database and other files stay.
        #expect(account.exists(account.storeFolder.appending(path: "default.store")))
        #expect(account.exists(account.storeFolder.appending(path: "other.bak")))
        #expect(account.exists(account.tmp.appending(path: "notes.txt")))
    }

    // The daily overdue reminder kept firing after a delete, and a route's
    // geofences stayed if the app was killed mid-route.
    @Test func notificationsGeofencesTheRouteAndTheWidgetAreCleared() throws {
        let account = try Account()
        defer { account.removeFiles() }
        #expect(account.routeStore.isActive)
        #expect(account.eraser().eraseAll().isEmpty)
        #expect(account.notifications.pending.isEmpty)
        #expect(account.notifications.delivered.isEmpty)
        #expect(account.regions.monitoredRegions.isEmpty)
        #expect(!account.routeStore.isActive)
        // Ended by the eraser, which also clears every Live Activity, not just
        // by the route store noticing its route was deleted.
        #expect(account.surfaces.calls.last == "clear")
        #expect(account.widgetCleared)
    }

    // The "PlowR" calendar, with every client's name and address, was left.
    @Test func thePlowRCalendarIsErased() throws {
        let account = try Account()
        defer { account.removeFiles() }
        #expect(account.eraser().eraseAll().isEmpty)
        #expect(account.calendarErased)
    }

    // Through the real calendar sync, with a calendar in memory.
    @Test func thePlowRCalendarsEventsAreGone() async throws {
        let account = try Account()
        defer { account.removeFiles() }
        let calendar = FakeVisitCalendarStore()
        let sync = CalendarSync(store: calendar, defaults: account.defaults)
        sync.configure(context: account.context)
        sync.operatorID = "op"
        await sync.setEnabled(true)
        #expect(calendar.events.count == 1, "the account's visit wasn't added, so this checks nothing")
        var eraser = account.eraser()
        eraser.eraseCalendar = sync.eraseAll
        #expect(eraser.eraseAll().isEmpty)
        #expect(calendar.events.isEmpty)
        #expect(!calendar.hasCalendar)
    }

    // Preferences say which calendar is PlowR's, even renamed: gone first,
    // the calendar couldn't be found to remove.
    @Test func theCalendarGoesBeforeThePreferences() throws {
        let account = try Account()
        defer { account.removeFiles() }
        var preferencesWereThere = false
        var eraser = account.eraser()
        eraser.eraseCalendar = { [defaults = account.defaults] in
            preferencesWereThere = defaults.object(forKey: "userRole") != nil
        }
        #expect(eraser.eraseAll().isEmpty)
        #expect(preferencesWereThere)
        #expect(account.defaults.object(forKey: "userRole") == nil)
    }

    @Test func aCalendarThatCantBeErasedIsReported() throws {
        let account = try Account()
        defer { account.removeFiles() }
        var eraser = account.eraser()
        eraser.eraseCalendar = { throw CocoaError(.fileWriteUnknown) }
        var signedOut = false
        let failures = eraser.eraseAll(thenSignOut: { signedOut = true })
        #expect(failures.map(\.step) == [AccountEraser.calendarStep])
        #expect(!signedOut)
        #expect(account.defaults.object(forKey: "userRole") != nil)
    }

    // Photos are kept as files beside the database (external storage), which an
    // in-memory store never writes. An on-disk store checks those go too.
    @Test func photoFilesBesideTheDatabaseAreDeleted() throws {
        let account = try Account()
        defer { account.removeFiles() }
        let schema = Schema(PlowRApp.models)
        let disk = try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, url: account.storeFolder.appending(path: "photos.store"), cloudKitDatabase: .none))
        disk.mainContext.insert(StopPhoto(operatorID: "op", clientID: "c", routeID: "r", isBefore: true,
                                          imageData: Data(repeating: 7, count: 1_000_000)))
        try disk.mainContext.save()
        let external = account.storeFolder.appending(path: ".photos_SUPPORT/_EXTERNAL_DATA")
        let before = (try? FileManager.default.contentsOfDirectory(atPath: external.path)) ?? []
        #expect(!before.isEmpty, "the photo wasn't stored as a file, so this test checks nothing")
        var eraser = account.eraser()
        eraser.context = disk.mainContext
        #expect(eraser.eraseAll().isEmpty)
        let after = (try? FileManager.default.contentsOfDirectory(atPath: external.path)) ?? []
        #expect(after.isEmpty, "photo files left: \(after)")
    }

    @Test func signedOutOnlyWhenEverythingIsGone() throws {
        let account = try Account()
        defer { account.removeFiles() }
        var signedOut = false
        #expect(account.eraser().eraseAll(thenSignOut: { signedOut = true }).isEmpty)
        #expect(signedOut)
    }

    // On a signed build the database is in the app-group container, not in
    // Application Support, so its own folder is swept for archives too.
    @Test func archivesAreSweptBesideTheLiveDatabase() throws {
        let account = try Account()
        defer { account.removeFiles() }
        let schema = Schema(PlowRApp.models)
        let disk = try ModelContainer(for: schema, configurations: ModelConfiguration(
            schema: schema, url: account.storeFolder.appending(path: "live.store"), cloudKitDatabase: .none))
        let paths = AccountEraser.archiveFolders(for: disk).map(\.standardizedFileURL.path)
        #expect(paths.contains(account.storeFolder.standardizedFileURL.path))
        #expect(paths.contains(URL.applicationSupportDirectory.standardizedFileURL.path))
        // An in-memory store has no folder to sweep.
        #expect(AccountEraser.archiveFolders(for: account.container).count == 1)
    }

    // A folder that exists but can't be read is a failure, not "nothing there":
    // its PDFs would otherwise stay behind while the user is signed out.
    @Test func anUnreadableFolderIsReportedNotSkipped() throws {
        let account = try Account()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: account.tmp.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: account.tmp.path)
            account.removeFiles()
        }
        var signedOut = false
        let failures = account.eraser().eraseAll(thenSignOut: { signedOut = true })
        #expect(failures.map(\.step) == ["shared PDFs"])
        #expect(!signedOut)
    }

    // A folder that isn't there has nothing in it to remove: not a failure.
    @Test func aMissingFolderIsNotAFailure() throws {
        let account = try Account()
        defer { account.removeFiles() }
        var eraser = account.eraser()
        eraser.temporaryDirectory = account.folder.appending(path: "no-tmp")
        eraser.archiveFolders = [account.folder.appending(path: "no-store")]
        #expect(eraser.eraseAll().isEmpty)
    }

    // A step that fails is reported and the others still run. Preferences are
    // kept, so the app stays on Settings to say what's left and to retry.
    @Test func aFailedStepIsReportedAndTheRestStillRun() throws {
        let account = try Account()
        let locked = account.folder.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let stuck = locked.appending(path: "clientWorkOrders.json")
        try Data("[]".utf8).write(to: stuck)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            account.removeFiles()
        }
        var eraser = account.eraser()
        eraser.workOrdersFile = stuck
        var signedOut = false
        let failures = eraser.eraseAll(thenSignOut: { signedOut = true })
        #expect(failures.map(\.step) == ["work orders"])
        #expect(!signedOut)
        #expect(!account.exists(account.tmp.appending(path: "INV-0001.pdf")))
        #expect(try count(Client.self, in: account.context) == 0)
        #expect(account.notifications.pending.isEmpty)
        #expect(account.regions.monitoredRegions.isEmpty)
        #expect(account.widgetCleared)
        #expect(account.defaults.object(forKey: "userRole") != nil)
    }
}
