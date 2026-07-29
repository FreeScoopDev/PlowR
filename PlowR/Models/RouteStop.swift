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

    init(order: Int, customName: String, customAddress: String = "", customPhone: String = "") {
        self.order = order
        self.clientName = customName
        self.clientPhone = customPhone
        self.clientAddress = customAddress
        self.isCustomStop = true
    }
}
