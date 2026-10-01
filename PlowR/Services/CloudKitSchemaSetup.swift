#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Puts every record type and field of PlowR's models into iCloud's
/// Development database, from the model itself, so it can be deployed to
/// Production before a release. A debug build only (Xcode builds use
/// Development; TestFlight and the App Store use Production).
///
/// iCloud's Production database can't add a field by itself: a release whose
/// models have one it lacks can't sync records that set it, and nothing in
/// the app says so. Development learns fields as records are saved, so a new
/// type or a field never given a value there was missing from the deploy.
/// Apple's `initializeCloudKitSchema()` creates them all, from a throwaway
/// store, without touching the app's own.
enum CloudKitSchemaSetup {
    static func run() throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PlowRApp.models) else {
            throw CocoaError(.featureUnsupported)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaSetup-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: PlowRApp.iCloudContainer)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "PlowRSchemaSetup", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        defer {
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: url)
        }
        try container.initializeCloudKitSchema(options: [])
    }
}
#endif
