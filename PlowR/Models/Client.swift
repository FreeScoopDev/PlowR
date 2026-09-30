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
    var defaultStopNotes: String = ""  // auto-copied to RouteStop on route creation

    // Client badges / billing preferences
    var preferredPayment: String = ""   // "cash", "check", "zelle", "card", or ""
    var isComped: Bool = false
    var defaultDiscountPercent: Double = 0.0
    var email: String = ""
    var tags: [String] = []
    var notes: String = ""          // general CRM notes, not shown on route
    var isActive: Bool = true
    var lastMessageSentAt: Date? = nil
    var clientRespondedAt: Date? = nil
    var expectedServiceIDs: [String] = []  // ServiceItem IDs this client typically needs

    var averageServiceMinutes: Double {
        guard totalVisits > 0 else { return 0 }
        return totalServiceMinutes / Double(totalVisits)
    }

    @Relationship(deleteRule: .cascade, inverse: \PropertyZone.client) var zones: [PropertyZone]?

    var sortedZones: [PropertyZone] {
        (zones ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The mapped zones, as pricing reads them.
    var pricingZones: [InvoiceLines.Zone] {
        sortedZones.map { InvoiceLines.Zone(label: $0.label, areaSquareFeet: $0.areaSquareFeet) }
    }

    init(name: String, phone: String, address: String, operatorID: String) {
        self.name = name
        self.phone = phone
        self.address = address
        self.operatorID = operatorID
    }
}

extension Client {
    /// The clients a route can be built from: this operator's active clients,
    /// by name. The 1.1.0 notes promised inactive clients are hidden from route
    /// building; both route pickers listed them anyway, with no marker.
    static func routable(from clients: [Client], operatorID: String) -> [Client] {
        clients
            .filter { $0.operatorID == operatorID && $0.isActive }
            .sorted { $0.name < $1.name }
    }

    /// The clients to stop at for these visits, in the visits' order: each
    /// visit's client if it's this operator's and active. Also how many visits
    /// were left out because their client is inactive, so the user can be told.
    static func routeClients(for visits: [ScheduledVisit], from clients: [Client],
                             operatorID: String) -> (clients: [Client], skippedInactive: Int) {
        var chosen: [Client] = []
        var skipped = 0
        for visit in visits {
            guard let client = clients.first(where: { $0.id.uuidString == visit.clientID && $0.operatorID == operatorID })
            else { continue }
            if client.isActive { chosen.append(client) } else { skipped += 1 }
        }
        return (chosen, skipped)
    }
}
