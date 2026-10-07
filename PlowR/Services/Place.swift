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
nonisolated struct Place: Equatable {
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
    /// A property marked inactive is off its routes and not booked. (The
    /// main place is the client's, whose own Active switch covers it.)
    var isActive = true

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
              expectedServiceIDs: property.expectedServiceIDs, zones: [], isMain: false,
              isActive: property.isActive)
    }

    /// `client`'s place with `propertyID`: their main one for an empty ID or
    /// their own, nil when it's missing.
    static func of(_ client: Client, propertyID: String) -> Place? {
        if isMain(propertyID, of: client) { return main(of: client) }
        return (client.properties ?? []).first { $0.id.uuidString == propertyID }.map { of($0) }
    }

    /// The ID of `client`'s place with `propertyID`, found or not: which
    /// place work was at, as the Service Log keeps it.
    static func id(of client: Client, propertyID: String) -> String {
        propertyID.isEmpty ? client.id.uuidString : propertyID
    }

    /// `id(of:propertyID:)` for a stop, without fetching its client.
    static func id(ofStop stop: RouteStop) -> String {
        stop.propertyID.isEmpty ? stop.clientID.uuidString : stop.propertyID
    }

    static func isMain(_ propertyID: String, of client: Client) -> Bool {
        propertyID.isEmpty || propertyID == client.id.uuidString
    }

    /// The client's places work can be booked at: the main one, then their
    /// active properties in order.
    static func all(of client: Client) -> [Place] {
        [main(of: client)] + ordered(client.properties ?? []).filter(\.isActive).map { of($0) }
    }

    /// What a picker offers for something already at `propertyID`: the
    /// bookable places, and that one too if it has since been made inactive,
    /// so the picker still shows where it is.
    static func choices(of client: Client, keeping propertyID: String) -> [Place] {
        let places = all(of: client)
        guard let kept = of(client, propertyID: propertyID), !places.contains(kept) else { return places }
        return places + [kept]
    }

    /// Properties in the order the business put them in.
    static func ordered(_ properties: [Property]) -> [Property] {
        properties.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    /// One client's one place, as a picker tells stops apart: a client can
    /// be on a route once at each of their places.
    static func key(clientID: UUID, propertyID: String) -> String {
        "\(clientID.uuidString)|\(propertyID.isEmpty ? clientID.uuidString : propertyID)"
    }

    /// The property ID a stop or visit keeps for this place: empty for the main one.
    var storedID: String { isMain ? "" : id }

    /// What a route list or picker calls a stop there: the client's name,
    /// and the place's label when it isn't the main one.
    func title(for clientName: String) -> String {
        isMain ? clientName : "\(clientName) · \(label)"
    }
}

/// A form field filled in from the place chosen (a new visit's notes and
/// time): it follows each place picked while it still shows what was last
/// filled in, and stays as it is once typed over.
struct PlaceFill<Value: Equatable>: Equatable {
    private(set) var filled: Value

    init(_ filled: Value) { self.filled = filled }

    mutating func follow(_ field: inout Value, to value: Value) {
        guard field == filled else { return }
        field = value
        filled = value
    }
}
