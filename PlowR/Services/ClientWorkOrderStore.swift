import Foundation

struct ClientWorkOrder: Codable, Identifiable {
    var id: UUID = UUID()
    var businessName: String
    var businessPhone: String
    var category: String
    var propertyAddress: String
    var totalAreaSqFt: Double
    var notes: String
    var submittedAt: Date
    var messageText: String
}

@Observable
final class ClientWorkOrderStore {
    private(set) var orders: [ClientWorkOrder] = []
    private let fileURL: URL
    private let defaults: UserDefaults

    /// The client's own contact details, kept in settings for the next
    /// request (WorkOrderRequestView).
    static let detailKeys = ["clientName", "clientPhone", "clientEmail"]
    private static let legacyKey = "clientWorkOrders"

    init(fileURL: URL = ClientWorkOrderStore.fileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        load()
    }

    func add(_ order: ClientWorkOrder) {
        orders.insert(order, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        offsets.sorted(by: >).forEach { orders.remove(at: $0) }
        save()
    }

    func delete(_ order: ClientWorkOrder) {
        orders.removeAll { $0.id == order.id }
        save()
    }

    /// Delete My Data, for a client: every saved request and the contact
    /// details kept for the next one. A business deletes everything,
    /// these included, with Delete Account & Data (AccountEraser).
    func eraseAll() throws {
        orders = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        for key in Self.detailKeys + [Self.legacyKey] { defaults.removeObject(forKey: key) }
    }

    // MARK: - Storage

    static var fileURL: URL {
        let fm = FileManager.default
        let support = URL.applicationSupportDirectory
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("clientWorkOrders.json")
    }

    private func load() {
        let url = fileURL

        // One-time migration from UserDefaults (unencrypted) to protected file
        if !FileManager.default.fileExists(atPath: url.path),
           let legacyData = defaults.data(forKey: Self.legacyKey) {
            try? legacyData.write(to: url, options: [.atomic, .completeFileProtection])
            defaults.removeObject(forKey: Self.legacyKey)
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ClientWorkOrder].self, from: data)
        else { return }
        orders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(orders) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
