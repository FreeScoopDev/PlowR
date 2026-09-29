import CoreData
import Foundation

/// Moves a database that can't be opened aside instead of deleting it, and
/// only when that's the right thing to do.
///
/// Where: the store's own configured location. The archive step used to look
/// in Application Support, but on a signed build SwiftData keeps the store in
/// the app-group container, so nothing moved and the app stopped at every launch.
///
/// When: only for a store made by an older model that can't be migrated to this
/// one, even without iCloud. A store that can't be read yet (a locked phone just
/// after a restart), one that matches the model, or one that opens without iCloud
/// failed for some other reason. Moving it aside would hide the user's data
/// behind an empty app, so it's left where it is.
///
/// `nonisolated`: file checks and moves only, run before any view exists.
nonisolated enum StoreArchive {

    /// Why a store that failed to open is, or isn't, moved aside.
    enum Verdict: Equatable {
        case missing, unreadable, matchesModel, opensWithoutICloud
        /// From an older model and can't be migrated: the only case that's archived.
        case cannotBeMigrated
    }

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

    /// Judges a store that failed to open. `opensLocally` tries opening it with
    /// iCloud off, which also migrates it if it can be.
    static func verdict(storeAt url: URL, model: NSManagedObjectModel?, opensLocally: () -> Bool) -> Verdict {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let model,
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        else { return .unreadable }
        if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) { return .matchesModel }
        if opensLocally() { return .opensWithoutICloud }
        return .cannotBeMigrated
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
