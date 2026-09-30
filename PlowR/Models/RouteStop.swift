import Foundation
import SwiftData

@Model
final class RouteStop {
    var id: UUID = UUID()
    var order: Int = 0
    var clientID: UUID = UUID()
    var clientName: String = ""
    var clientPhone: String = ""
    var clientAddress: String = ""
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    var isCustomStop: Bool = false
    var targetMinutes: Int = 0
    var actualMinutes: Int = 0
    var completedServiceIDs: [String] = []
    var completedNotes: String = ""
    var stopNotes: String = ""       // persistent operator reminders shown during route
    var equipmentNotes: String = ""  // equipment/blade flags shown during route
    /// The services this stop needs on this route, when it has its own list
    /// (`hasOwnServices`). Otherwise it follows its client's usual services.
    /// StopServices is the rule.
    var expectedServiceIDs: [String] = []
    var hasOwnServices: Bool = false
    /// The property the stop is at (Place): empty or the client's ID for
    /// their own address.
    var propertyID: String = ""
    var route: PlowRoute?

    init(order: Int, client: Client) {
        self.order = order
        self.clientID = client.id
        self.clientName = client.name
        self.clientPhone = client.phone
        self.clientAddress = client.address
        self.latitude = client.latitude
        self.longitude = client.longitude
        self.isCustomStop = false
    }

    /// A stop at one of `client`'s places.
    convenience init(order: Int, client: Client, place: Place) {
        self.init(order: order, client: client)
        propertyID = place.isMain ? "" : place.id
        clientAddress = place.address
        latitude = place.latitude
        longitude = place.longitude
        // A new stop starts with the place's route notes (gate codes and the
        // like), whichever screen makes it.
        stopNotes = place.stopNotes
    }

    /// Which of its client's places it's at, as the client picker keys them.
    var placeKey: String { Place.key(clientID: clientID, propertyID: propertyID) }

    init(order: Int, customName: String, customAddress: String = "", customPhone: String = "") {
        self.order = order
        self.clientName = customName
        self.clientPhone = customPhone
        self.clientAddress = customAddress
        self.isCustomStop = true
    }
}
