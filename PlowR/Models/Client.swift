import Foundation
import SwiftData

@Model
final class Client {
    var id: UUID = UUID()
    var name: String = ""
    var phone: String = ""
    var address: String = ""
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var operatorID: String = ""
    var createdAt: Date = Date()

    // Service history — written by ActiveRouteView on stop completion
    var totalVisits: Int = 0
    var totalServiceMinutes: Double = 0.0
    var lastServiceDate: Date? = nil

    // Route behavior preferences
    var skipNotificationPrompt: Bool = false
    var goalMinutes: Int = 0

    var averageServiceMinutes: Double {
        guard totalVisits > 0 else { return 0 }
        return totalServiceMinutes / Double(totalVisits)
    }

    @Relationship(deleteRule: .cascade, inverse: \PropertyZone.client) var zones: [PropertyZone]?

    var sortedZones: [PropertyZone] {
        (zones ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    init(name: String, phone: String, address: String, operatorID: String) {
        self.name = name
        self.phone = phone
        self.address = address
        self.operatorID = operatorID
    }
}
