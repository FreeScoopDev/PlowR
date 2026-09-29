import CoreData
import Foundation

/// Moves a database that can't be opened aside instead of deleting it, and
/// only when that's the right thing to do.
///
/// Where: the store's own configured location. The archive step used to look
/// in Application Support, but on a signed build SwiftData keeps the store in
/// the app-group container, so nothing moved and the app stopped at every launch.
///
/// When: only when Core Data says the store was made by another model and can't
/// be migrated to this one, even with iCloud off. A store that can't be read yet
/// (a locked phone just after a restart), one that matches the model, one that
/// opens without iCloud, or one that fails for another reason (a full disk)
/// is left where it is. Moving it aside would hide the user's data behind an
/// empty app.
///
/// `nonisolated`: file checks and moves only, run before any view exists.
nonisolated enum StoreArchive {

    /// Why a store that failed to open is, or isn't, moved aside.
    enum Verdict: Equatable {
        case missing, unreadable, matchesModel, opensWithoutICloud
        /// Opening it without iCloud failed, but not because of the model.
        case failedForAnotherReason(code: Int)
        /// Core Data can't migrate it to this model: the only case archived.
        case cannotBeMigrated
    }

    /// Core Data's errors for a store whose model can't be migrated to this
    /// one: no mapping can be inferred, the source model is missing, or the
    /// versions don't match. Not the generic migration error: that's also what
    /// a migration that couldn't write reports (seen with read-only files).
    static let migrationErrorCodes: Set<Int> = [
        NSPersistentStoreIncompatibleVersionHashError, NSMigrationMissingSourceModelError,
        NSMigrationMissingMappingModelError, NSInferredMappingModelError,
    ]

    /// The parts of the store at `url`, the database first: it, its write-ahead
    /// log and shared memory, and the folder of photos kept beside it as files.
    static func parts(of url: URL) -> [URL] {
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        let base = url.deletingPathExtension().lastPathComponent
        return [url,
                folder.appending(path: "\(name)-wal"),
                folder.appending(path: "\(name)-shm"),
                folder.appending(path: ".\(base)_SUPPORT")]
    }

    /// Judges a store that failed to open, trying it once more with iCloud off,
    /// which also migrates it if it can be.
    static func verdict(storeAt url: URL, model: NSManagedObjectModel?) -> Verdict {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let model,
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        else { return .unreadable }
        if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) { return .matchesModel }
        guard let error = openLocally(storeAt: url, model: model) else { return .opensWithoutICloud }
        return isMigrationFailure(error) ? .cannotBeMigrated : .failedForAnotherReason(code: error.code)
    }

    /// One of those errors, anywhere in the chain of underlying errors, and no
    /// sign of a file problem (no permission, a full disk) or a database fault
    /// (an SQLite error), either of which means the model isn't the problem.
    static func isMigrationFailure(_ error: NSError) -> Bool {
        var codes: [Int] = []
        var databaseFault = false
        // Core Data nests errors three ways: one underlying error, or a list
        // under "detailed" or "multiple underlying" errors. Walk them all.
        var pending: [NSError] = [error]
        while let current = pending.popLast() {
            if current.domain == NSCocoaErrorDomain { codes.append(current.code) }
            if current.userInfo[NSSQLiteErrorDomain] != nil { databaseFault = true }
            if let under = current.userInfo[NSUnderlyingErrorKey] as? NSError { pending.append(under) }
            pending += current.userInfo[NSDetailedErrorsKey] as? [NSError] ?? []
            pending += current.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] ?? []
        }
        let fileProblem = codes.contains { (NSFileErrorMinimum...NSFileErrorMaximum).contains($0) && $0 != 0 }
        if databaseFault || fileProblem || codes.contains(NSSQLiteError) { return false }
        return codes.contains { migrationErrorCodes.contains($0) }
    }

    /// Opens the store with Core Data, iCloud off and history tracking on (as
    /// iCloud sync leaves it, so it isn't forced read-only), migrating it if it
    /// can, then closes it again. The error if it can't be opened.
    static func openLocally(storeAt url: URL, model: NSManagedObjectModel) -> NSError? {
        let container = NSPersistentContainer(name: "StoreCheck", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        var failure: NSError?
        container.loadPersistentStores { _, error in failure = error as NSError? }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        return failure
    }

    /// Moves each part that exists to `<part>.<stamp>.bak` beside it, the
    /// database first. All or nothing: if a part won't move, the parts already
    /// moved are put back, because a new database beside an old log is corrupt.
    @discardableResult
    static func archive(storeAt url: URL, stamp: Int, fileManager: FileManager = .default) -> Bool {
        var moved: [(from: URL, to: URL)] = []
        for part in parts(of: url) where fileManager.fileExists(atPath: part.path) {
            let destination = part.deletingLastPathComponent().appending(path: "\(part.lastPathComponent).\(stamp).bak")
            do {
                try fileManager.moveItem(at: part, to: destination)
                moved.append((part, destination))
            } catch {
                for (from, to) in moved.reversed() { try? fileManager.moveItem(at: to, to: from) }
                return false
            }
        }
        return true
    }
}
