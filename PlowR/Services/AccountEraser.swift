import CoreLocation
import Foundation
import SwiftData
import UserNotifications

/// Pending and delivered notifications, as `UNUserNotificationCenter` holds
/// them. A protocol so a test can check the delete path clears them.
protocol NotificationClearing {
    func removeAllPendingNotificationRequests()
    func removeAllDeliveredNotifications()
}

extension UNUserNotificationCenter: NotificationClearing {}

/// The geofences being monitored, as `CLLocationManager` holds them (for the
/// whole app, not one manager). A protocol for the same reason.
protocol RegionMonitoring {
    var monitoredRegions: Set<CLRegion> { get }
    func stopMonitoring(for region: CLRegion)
}

extension CLLocationManager: RegionMonitoring {}

/// Delete Account & Data (App Review guideline 5.1.1(v)): removes everything
/// PlowR keeps on this device, and reports anything it couldn't.
///
/// Every place the app stores something is covered here: every SwiftData
/// model (the list the schema is built from, so a new model can't be missed),
/// every preference (the whole domain, so a new key can't be missed either),
/// the work-orders file, notifications, geofences, shared PDFs, database
/// archives, the route in progress, the widget's copy of it and the "PlowR"
/// calendar. `AccountEraserTests` writes each one and checks it's gone.
///
/// Not here yet: the iCloud copy.
@MainActor
struct AccountEraser {
    /// A step that failed. The other steps still run.
    struct Failure: Equatable {
        var step: String
        var reason: String
    }

    /// Settings shows this step's reason: only the user can fix it.
    static let calendarStep = "calendar events"

    var context: ModelContext
    var models: [any PersistentModel.Type] = PlowRApp.models
    var defaults: UserDefaults = .standard
    /// The preferences domain removed whole.
    var defaultsDomain: String? = Bundle.main.bundleIdentifier
    var fileManager: FileManager = .default
    var workOrdersFile: URL = ClientWorkOrderStore.fileURL
    /// Where shared invoices, proposals and reports are written as PDFs.
    var temporaryDirectory: URL = FileManager.default.temporaryDirectory
    /// Where `default.store…bak` archives, and archived photo folders, can be:
    /// the store's own folder, and Application Support, where the archive step
    /// used to put them.
    var archiveFolders: [URL]
    var notifications: any NotificationClearing = UNUserNotificationCenter.current()
    var regions: any RegionMonitoring = CLLocationManager()
    var routeStore: ActiveRouteStore = .shared
    var clearWidget: @MainActor () -> Void = WidgetDataStore.clear
    /// The "PlowR" calendar and every event PlowR added: client names and
    /// addresses, with reminders.
    var eraseCalendar: @MainActor () throws -> Void = { try CalendarSync.shared.eraseAll() }

    /// Removes everything it can. Returns the steps that failed; empty means
    /// everything on this device is gone.
    ///
    /// Preferences go last, and only when every other step worked: removing
    /// them resets the app to its first screen, which would hide the message
    /// saying what's left, and the role kept there lets the user try again.
    func eraseAll() -> [Failure] {
        var failures: [Failure] = []
        func attempt(_ step: String, _ body: () throws -> Void) {
            do { try body() } catch { failures.append(Failure(step: step, reason: error.localizedDescription)) }
        }
        // The route first: ending it shows its last progress, read from its models.
        routeStore.eraseAll()
        for model in models {
            attempt("\(model) records") { try deleteAll(model) }
        }
        // `delete(model:)` is documented to take effect at the next save. On
        // iOS 26 the records are already gone before this (a test that drops
        // the save stays green), so it is kept for the documented behaviour,
        // and so a failed save is reported rather than left to autosave.
        attempt("saving the deletions") { try context.save() }
        failures += eraseFromDevice()
        // Before preferences: they say which calendar is PlowR's.
        attempt(Self.calendarStep) { try eraseCalendar() }
        if failures.isEmpty, let defaultsDomain {
            defaults.removePersistentDomain(forName: defaultsDomain)
        }
        return failures
    }

    /// Remove from This Device: everything PlowR keeps on this device only,
    /// and nothing in iCloud. No record is deleted through the database:
    /// that's what tells iCloud to delete it everywhere. Instead iCloud sync
    /// is turned off here and the database's files are removed at the next
    /// launch, before it opens (DeviceSync). The "PlowR" calendar is left:
    /// it's in the user's calendars, in iCloud for most, so removing it here
    /// would remove it on their other devices too.
    func removeFromThisDevice() -> [Failure] {
        var failures: [Failure] = []
        routeStore.eraseAll()
        failures += eraseFromDevice()
        // Only when everything else went: the database can't be got back, and
        // the failures stay on screen (Settings) to retry.
        if failures.isEmpty {
            if let defaultsDomain { defaults.removePersistentDomain(forName: defaultsDomain) }
            // After the preferences go: these are about the device, not the account.
            DeviceSync.scheduleRemoval(defaults: defaults)
        }
        return failures
    }

    /// Erases, then signs out only if nothing failed (as `eraseAll(thenSignOut:)`).
    func removeFromThisDevice(thenSignOut signOut: () -> Void) -> [Failure] {
        let failures = removeFromThisDevice()
        if failures.isEmpty { signOut() }
        return failures
    }

    /// What's on this device only: files, notifications, geofences, the widget.
    private func eraseFromDevice() -> [Failure] {
        var failures: [Failure] = []
        func attempt(_ step: String, _ body: () throws -> Void) {
            do { try body() } catch { failures.append(Failure(step: step, reason: error.localizedDescription)) }
        }
        attempt("work orders") { try removeIfPresent(workOrdersFile) }
        // Documents and exported spreadsheets (CSVExport) left from sharing.
        attempt("shared files") {
            for file in try files(in: temporaryDirectory, where: { ["pdf", "csv"].contains($0.pathExtension) }) {
                attempt("shared file \(file.lastPathComponent)") { try removeIfPresent(file) }
            }
        }
        for folder in archiveFolders {
            attempt("database archives in \(folder.lastPathComponent)") {
                let archives = try files(in: folder) { Self.isArchive($0) }
                for file in archives {
                    attempt("database archive \(file.lastPathComponent)") { try removeIfPresent(file) }
                }
            }
        }
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        for region in regions.monitoredRegions { regions.stopMonitoring(for: region) }
        clearWidget()
        return failures
    }

    /// Erases everything, then signs out only if nothing failed, so what's
    /// left can be retried while still signed in.
    func eraseAll(thenSignOut signOut: () -> Void) -> [Failure] {
        let failures = eraseAll()
        if failures.isEmpty { signOut() }
        return failures
    }

    /// The folders the database and its `.bak` archives can be in: the store's
    /// own (the app-group container on a signed build) and Application Support,
    /// where the archive step has been putting them.
    static func archiveFolders(for container: ModelContainer) -> [URL] {
        var folders = [URL.applicationSupportDirectory]
        for configuration in container.configurations where configuration.url.path != "/dev/null" {
            let folder = configuration.url.deletingLastPathComponent()
            if !folders.contains(where: { $0.standardizedFileURL.path == folder.standardizedFileURL.path }) {
                folders.append(folder)
            }
        }
        return folders
    }

    /// A `.bak` archive that StoreArchive made: one of the database's files,
    /// or the folder of photos kept beside it.
    nonisolated static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return url.pathExtension == "bak" && (name.hasPrefix("default.store") || name.hasPrefix(".default_SUPPORT."))
    }

    private func deleteAll<T: PersistentModel>(_ model: T.Type) throws {
        try context.delete(model: model)
    }

    /// The files in `folder` that `keep` accepts. No folder means no files;
    /// a folder that can't be read is an error, not "nothing there".
    private func files(in folder: URL, where keep: (URL) -> Bool) throws -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter(keep)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
