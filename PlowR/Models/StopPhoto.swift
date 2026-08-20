import Foundation
import SwiftData

@Model
final class StopPhoto {
    var id: UUID = UUID()
    var operatorID: String = ""
    var clientID: String = ""      // for querying all photos for a client
    var routeID: String = ""       // for querying photos from a specific route
    var isBefore: Bool = true      // before or after service
    var caption: String = ""
    var takenAt: Date = Date()

    @Attribute(.externalStorage)
    var imageData: Data = Data()

    init(operatorID: String, clientID: String, routeID: String, isBefore: Bool, imageData: Data) {
        self.operatorID = operatorID
        self.clientID = clientID
        self.routeID = routeID
        self.isBefore = isBefore
        self.imageData = imageData
    }
}
