import Foundation
import Testing
@testable import PlowR

/// Delete My Data, for a client: their saved requests and the contact
/// details kept for the next one.
struct ClientDataTests {
    @Test func deleteMyDataRemovesRequestsAndContactDetails() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ClientDataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "clientWorkOrders.json")
        let defaults = try #require(UserDefaults(suiteName: "ClientDataTests-\(UUID().uuidString)"))
        for key in ClientWorkOrderStore.detailKeys { defaults.set("Pat", forKey: key) }
        defaults.set("kept", forKey: "userRole")

        let store = ClientWorkOrderStore(fileURL: file, defaults: defaults)
        store.add(ClientWorkOrder(businessName: "North Plow", businessPhone: "555-0100", category: "snow",
                                  propertyAddress: "1 Main St", totalAreaSqFt: 900, notes: "", submittedAt: Date(),
                                  messageText: "Hi, this is Pat"))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(ClientWorkOrderStore(fileURL: file, defaults: defaults).orders.count == 1)

        try store.eraseAll()
        #expect(store.orders.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(ClientWorkOrderStore.detailKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        #expect(ClientWorkOrderStore(fileURL: file, defaults: defaults).orders.isEmpty)
        #expect(defaults.string(forKey: "userRole") == "kept")      // only the client's data
        try store.eraseAll()                                          // nothing left: no error
    }

    // A file that can't be removed: the contact details still go, and the
    // requests aren't shown as gone while they're still on disk.
    @Test func aStuckFileStillLosesTheContactDetailsAndKeepsTheRequestsShown() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ClientDataTests-\(UUID().uuidString)")
        let locked = folder.appending(path: "locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let file = locked.appending(path: "clientWorkOrders.json")
        let defaults = try #require(UserDefaults(suiteName: "ClientDataTests-\(UUID().uuidString)"))
        for key in ClientWorkOrderStore.detailKeys { defaults.set("Pat", forKey: key) }
        defaults.set(Data(), forKey: "clientWorkOrders")       // a pre-file copy, from an old version
        let store = ClientWorkOrderStore(fileURL: file, defaults: defaults)
        store.add(ClientWorkOrder(businessName: "North Plow", businessPhone: "", category: "snow",
                                  propertyAddress: "1 Main St", totalAreaSqFt: 0, notes: "", submittedAt: Date(),
                                  messageText: ""))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: folder)
        }
        #expect(throws: (any Error).self) { try store.eraseAll() }
        #expect(ClientWorkOrderStore.detailKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        #expect(defaults.object(forKey: "clientWorkOrders") == nil)
        #expect(store.orders.count == 1)
    }
}
