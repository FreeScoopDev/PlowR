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
    private let storageKey = "clientWorkOrders"

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

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClientWorkOrder].self, from: data)
        else { return }
        orders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(orders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
