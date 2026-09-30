import Foundation
import SwiftData

/// One of a client's additional properties: a landlord's second house, a
/// business's second lot. A client's own address is their main property and
/// isn't a Property: it has the client's ID wherever a property ID is kept
/// (Place). So nothing moved when properties came, and a client with one
/// place is exactly as before.
@Model
final class Property {
    var id: UUID = UUID()
    var operatorID: String = ""
    /// What the business calls it: "Rental on Elm", "North lot".
    var label: String = ""
    var address: String = ""
    var latitude: Double = 0.0
    var longitude: Double = 0.0
    /// Copied to its route stops when they're made, as a client's are.
    var stopNotes: String = ""
    var goalMinutes: Int = 0
    var expectedServiceIDs: [String] = []
    var isActive: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var client: Client?

    init(label: String, address: String, operatorID: String) {
        self.label = label
        self.address = address
        self.operatorID = operatorID
    }
}
