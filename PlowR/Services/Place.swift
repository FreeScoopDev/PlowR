import Foundation

/// Where work for a client is done: their own address (the main property,
/// whose ID is the client's), or one of their additional properties. The one
/// rule for turning a client and a property ID into an address, a pin and
/// what the place expects, so stops, visits, the Service Log and pricing all
/// agree. An ID that's empty or the client's own is the main one.
///
/// An ID that's neither, and isn't one of their properties, is a place that's
/// missing: removed (its earlier visits keep its ID), or not synced here yet
/// (a stop can arrive from iCloud before its property). That is never taken
/// for the main one: a job there isn't the main house's, its stored address
/// isn't overwritten with the main one, and it isn't priced by the main
/// house's measurements.
struct Place: Equatable {
    let id: String
    let label: String
    let address: String
    let latitude: Double
    let longitude: Double
    let stopNotes: String
    let goalMinutes: Int
    let expectedServiceIDs: [String]
    let zones: [InvoiceLines.Zone]
    let isMain: Bool

    static func main(of client: Client) -> Place {
        Place(id: client.id.uuidString, label: "Main", address: client.address, latitude: client.latitude,
              longitude: client.longitude, stopNotes: client.defaultStopNotes, goalMinutes: client.goalMinutes,
              expectedServiceIDs: client.expectedServiceIDs, zones: client.pricingZones, isMain: true)
    }

    static func of(_ property: Property) -> Place {
        // Measured zones are the main property's only, for now: an additional
        // property is priced at the services' flat rates.
        Place(id: property.id.uuidString, label: property.label.isEmpty ? property.address : property.label,
              address: property.address, latitude: property.latitude, longitude: property.longitude,
              stopNotes: property.stopNotes, goalMinutes: property.goalMinutes,
              expectedServiceIDs: property.expectedServiceIDs, zones: [], isMain: false)
    }

    /// `client`'s place with `propertyID`: their main one for an empty ID or
    /// their own, nil when it's missing.
    static func of(_ client: Client, propertyID: String) -> Place? {
        if isMain(propertyID, of: client) { return main(of: client) }
        return (client.properties ?? []).first { $0.id.uuidString == propertyID }.map(of)
    }

    /// The ID of `client`'s place with `propertyID`, found or not: which
    /// place work was at, as the Service Log keeps it.
    static func id(of client: Client, propertyID: String) -> String {
        propertyID.isEmpty ? client.id.uuidString : propertyID
    }

    static func isMain(_ propertyID: String, of client: Client) -> Bool {
        propertyID.isEmpty || propertyID == client.id.uuidString
    }

    /// The client's places work can be booked at: the main one, then their
    /// active properties in order.
    static func all(of client: Client) -> [Place] {
        [main(of: client)] + (client.properties ?? [])
            .filter(\.isActive)
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
            .map(of)
    }
}
