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

    init() { load() }

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

    // MARK: - Storage

    static var fileURL: URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("clientWorkOrders.json")
    }

    private func load() {
        let url = Self.fileURL

        // One-time migration from UserDefaults (unencrypted) to protected file
        if !FileManager.default.fileExists(atPath: url.path),
           let legacyData = UserDefaults.standard.data(forKey: "clientWorkOrders") {
            try? legacyData.write(to: url, options: [.atomic, .completeFileProtection])
            UserDefaults.standard.removeObject(forKey: "clientWorkOrders")
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ClientWorkOrder].self, from: data)
        else { return }
        orders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(orders) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtection])
    }
}
