import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Remove from This Device: the data leaves this device and nothing in
/// iCloud is touched. No record is deleted through the database (that's what
/// tells iCloud to delete it everywhere); sync is turned off here and the
/// database's files go at the next launch, before it opens.
@MainActor
struct RemoveFromDeviceTests {
    typealias Account = AccountEraserTests.Account

    private func count<T: PersistentModel>(_ model: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    @Test func noRecordIsDeletedSoIcloudKeepsEverything() throws {
        let account = try Account()
        defer { account.removeFiles() }
        let before = try PlowRApp.models.map { try count($0, in: account.context) }
        #expect(account.eraser().removeFromThisDevice().isEmpty)
        let after = try PlowRApp.models.map { try count($0, in: ModelContext(account.container)) }
        #expect(after == before)
    }

    @Test func whatsOnlyOnThisDeviceGoesAndTheCalendarStays() throws {
        let account = try Account()
        defer { account.removeFiles() }
        var signedOut = false
        #expect(account.eraser().removeFromThisDevice(thenSignOut: { signedOut = true }).isEmpty)
        #expect(signedOut)
        #expect(!account.exists(account.workOrders))
        #expect(account.widgetCleared)
        #expect(account.regions.monitoredRegions.isEmpty)
        #expect(!account.routeStore.isActive)
        // The "PlowR" calendar is in the user's calendars, in iCloud for most:
        // removing it here would remove it from their other devices.
        #expect(!account.calendarErased)
        for key in Account.keys { #expect(account.defaults.object(forKey: key) == nil, "\(key)") }
        // Written after the preferences went: about the device, not the account.
        #expect(DeviceSync.isOff(account.defaults))
        #expect(DeviceSync.isRemovalPending(account.defaults))
    }

    // A step that fails: nothing scheduled, nobody signed out, and the
    // failures stay on screen to retry (the database can't be got back).
    @Test func aFailedStepSchedulesNothing() throws {
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
        #expect(eraser.removeFromThisDevice(thenSignOut: { signedOut = true }).map(\.step) == ["work orders"])
        #expect(!signedOut)
        #expect(!DeviceSync.isRemovalPending(account.defaults))
        #expect(!DeviceSync.isOff(account.defaults))
    }

    // Sync off opens the database with iCloud off, said so: SwiftData's
    // default (.automatic) picks the entitlements' container on a signed build.
    @Test func syncOffOpensTheSameFileWithICloudSaidOff() {
        let schema = Schema(PlowRApp.models)
        let offline = PlowRApp.offlineConfiguration(for: schema)
        #expect(offline.url == PlowRApp.localConfiguration(for: schema).url)
        let none = ModelConfiguration(schema: schema, cloudKitDatabase: .none).cloudKitDatabase
        let automatic = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic).cloudKitDatabase
        #expect(String(describing: offline.cloudKitDatabase) == String(describing: none))
        #expect(String(describing: none) != String(describing: automatic))
    }

    // MARK: - At the next launch

    private func storeFolder() throws -> (folder: URL, store: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RemoveFromDevice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = folder.appending(path: "default.store")
        for part in StoreArchive.parts(of: store) {
            if part.lastPathComponent.hasSuffix("_SUPPORT") {
                try FileManager.default.createDirectory(at: part.appending(path: "_EXTERNAL_DATA"),
                                                        withIntermediateDirectories: true)
            } else {
                try Data([1]).write(to: part)
            }
        }
        try Data([2]).write(to: folder.appending(path: "other.store"))
        return (folder, store)
    }

    @Test func theDatabaseFilesGoAtLaunchOnlyWhenAsked() throws {
        let (folder, store) = try storeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = try #require(UserDefaults(suiteName: "RemoveFromDevice-\(UUID().uuidString)"))
        // Not asked: nothing goes.
        #expect(!DeviceSync.removeDatabaseIfAsked(storeAt: store, defaults: defaults))
        #expect(StoreArchive.parts(of: store).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        DeviceSync.scheduleRemoval(defaults: defaults)
        #expect(DeviceSync.removeDatabaseIfAsked(storeAt: store, defaults: defaults))
        #expect(StoreArchive.parts(of: store).allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "other.store").path))
        #expect(!DeviceSync.isRemovalPending(defaults))     // done
        #expect(DeviceSync.isOff(defaults))                 // and sync stays off until turned on
    }

    // Only the photo folder won't go: the database and its log stay with it,
    // never a new database beside an old log.
    @Test func aFileThatCantGoLeavesTheDatabaseAndIsTriedAgain() throws {
        let (folder, store) = try storeFolder()
        let support = folder.appending(path: ".default_SUPPORT")
        let defaults = try #require(UserDefaults(suiteName: "RemoveFromDevice-\(UUID().uuidString)"))
        DeviceSync.scheduleRemoval(defaults: defaults)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: support.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support.path)
            try? FileManager.default.removeItem(at: folder)
        }
        #expect(DeviceSync.removeDatabaseIfAsked(storeAt: store, defaults: defaults))
        #expect(DeviceSync.isRemovalPending(defaults))
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "default.store-wal").path))
    }

    // With sync off, the fallback and the reopen after archiving open with
    // iCloud said off too; otherwise the usual unnamed local configuration.
    @Test func everyOpenWithSyncOffIsSaidOff() {
        let schema = Schema(PlowRApp.models)
        let none = String(describing: ModelConfiguration(schema: schema, cloudKitDatabase: .none).cloudKitDatabase)
        #expect(String(describing: PlowRApp.fallbackConfiguration(for: schema, syncOff: true).cloudKitDatabase) == none)
        #expect(String(describing: PlowRApp.fallbackConfiguration(for: schema, syncOff: false).cloudKitDatabase)
            == String(describing: PlowRApp.localConfiguration(for: schema).cloudKitDatabase))
    }

    @Test func turningSyncOnLeavesAPendingRemovalToFinish() throws {
        let defaults = try #require(UserDefaults(suiteName: "RemoveFromDevice-\(UUID().uuidString)"))
        DeviceSync.scheduleRemoval(defaults: defaults)
        #expect(DeviceSync.isOff(defaults))
        DeviceSync.turnOn(defaults: defaults)
        #expect(!DeviceSync.isOff(defaults))
        #expect(DeviceSync.isRemovalPending(defaults))      // the old database still goes first
    }
}
