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
    /// Marked lost: a lead or a quote that didn't turn into work (Pipeline).
    /// Nil for everyone else, and again when reopened.
    var lostAt: Date? = nil
    /// When they became a customer without anything in PlowR to show it: a
    /// client list imported as current customers (ClientImport). Nil for
    /// everyone else; their work says it (Pipeline).
    var customerSince: Date?
    /// When the map couldn't find their address (ImportPins): looked up once,
    /// never again on its own; the client is marked until they have a pin
    /// (`needsAddressFix`). The business likely knows why.
    var addressNotFoundAt: Date?
    var expectedServiceIDs: [String] = []  // ServiceItem IDs this client typically needs

    var averageServiceMinutes: Double {
        guard totalVisits > 0 else { return 0 }
        return totalServiceMinutes / Double(totalVisits)
    }

    @Relationship(deleteRule: .cascade, inverse: \PropertyZone.client) var zones: [PropertyZone]?
    /// Additional properties; the client's own address is their main one (Place).
    @Relationship(deleteRule: .cascade, inverse: \Property.client) var properties: [Property]?
    /// Their contracts (Contracts). Deleting the client deletes them or, with
    /// Keep Records, keeps the signed ones (ClientRemoval).
    @Relationship(deleteRule: .nullify, inverse: \Contract.client) var contracts: [Contract]?

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
    /// The map couldn't find their address and they still have no pin:
    /// marked for the business to fix (ImportPins). A pin, set on their page
    /// or by a corrected address, clears it.
    var needsAddressFix: Bool {
        addressNotFoundAt != nil && !address.isEmpty && !AddressPin.exists(latitude: latitude, longitude: longitude)
    }

    /// Their address, changed: a mark for the old one goes, and ImportPins
    /// looks the new one up once (one lookup per address).
    func changeAddress(to new: String) {
        if new != address { addressNotFoundAt = nil }
        address = new
    }

    /// They, or one of their properties, need an address fixed.
    var anyAddressNeedsFix: Bool {
        needsAddressFix || (properties ?? []).contains { $0.needsAddressFix }
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
        let stops = routeStops(for: visits, from: clients, operatorID: operatorID)
        return (stops.stops.map(\.client), stops.skippedInactive)
    }

    /// As `routeClients`, with each visit's place (Place): a stop goes where
    /// the visit was booked, the client's own address or one of their
    /// properties. A visit at a place missing here (its property not synced
    /// yet) is left off rather than sent to the main address. One at an
    /// inactive property is left off and counted, as an inactive client's is.
    static func routeStops(for visits: [ScheduledVisit], from clients: [Client], operatorID: String)
        -> (stops: [(client: Client, place: Place)], skippedInactive: Int) {
        var chosen: [(client: Client, place: Place)] = []
        var skipped = 0
        for visit in visits {
            guard let client = clients.first(where: { $0.id.uuidString == visit.clientID && $0.operatorID == operatorID })
            else { continue }
            if !client.isActive {
                skipped += 1
            } else if let place = Place.of(client, propertyID: visit.propertyID) {
                if place.isActive { chosen.append((client, place)) } else { skipped += 1 }
            }
        }
        return (chosen, skipped)
    }
}
