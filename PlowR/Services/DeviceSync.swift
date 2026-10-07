import Foundation

/// iCloud sync on this device, and removing PlowR's data from this device
/// alone (Settings → Delete Account & Data → Remove from This Device).
///
/// iCloud sync follows the device's iCloud account, not PlowR's sign-in, so
/// a copy wiped from a syncing device comes straight back. And deleting the
/// records through the database is what tells iCloud to delete them, from
/// every device (AccountEraser, checked on a device 2026-10-06). So removing
/// from this device only is two choices kept here, acted on at the next
/// launch, before the database opens (PlowRApp.makeContainer):
/// - **Sync off:** the database opens without iCloud, so nothing comes back
///   down and nothing goes up. Turning it on again brings everything back.
/// - **Remove the local database:** its files are deleted (never its
///   records, which iCloud would copy), then a fresh one is made.
/// Both are preferences outside what Delete Account & Data removes, written
/// after it: they're about this device, not the account.
nonisolated enum DeviceSync {
    static let offKey = "iCloudSyncOffOnThisDevice"
    static let removeKey = "removeLocalDatabaseAtLaunch"

    static func isOff(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: offKey) }

    /// Takes effect the next time PlowR opens: the database is opened once.
    static func setOff(_ off: Bool, defaults: UserDefaults = .standard) {
        defaults.set(off, forKey: offKey)
    }

    /// The local database will be removed at the next launch.
    static func isRemovalPending(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: removeKey) }

    /// Remove from This Device: sync off, and the local database removed at
    /// the next launch.
    static func scheduleRemoval(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: offKey)
        defaults.set(true, forKey: removeKey)
    }

    /// At launch, before the database opens: removes its files (the database,
    /// its log, and the photos kept beside it as files) if Remove from This
    /// Device asked. Returns whether a removal was asked. If a file can't be
    /// removed, it's asked again at the next launch, with sync still off.
    @discardableResult
    static func removeDatabaseIfAsked(storeAt url: URL, defaults: UserDefaults = .standard,
                                      fileManager: FileManager = .default) -> Bool {
        guard isRemovalPending(defaults) else { return false }
        var removedAll = true
        for part in StoreArchive.parts(of: url) where fileManager.fileExists(atPath: part.path) {
            do { try fileManager.removeItem(at: part) } catch { removedAll = false }
        }
        if removedAll { defaults.removeObject(forKey: removeKey) }
        return true
    }
}
