import Foundation
import SwiftData

@Model
final class StopPhoto {
    var id: UUID = UUID()
    var operatorID: String = ""
    var clientID: String = ""      // for querying all photos for a client
    var routeID: String = ""       // for querying photos from a specific route
    var recordID: String = ""      // the Service Log record (ServiceRecord) it shows the work of
    var checkID: String = ""       // or the below-trigger check (TriggerCheck) it shows
    var isBefore: Bool = true      // before or after service
    var caption: String = ""
    /// When it was saved in PlowR (despite the name: kept for older builds).
    var takenAt: Date = Date()
    /// When it was actually taken (PhotoCapture): the camera's moment, or a
    /// library photo's EXIF time. Nil when that isn't known.
    var capturedAt: Date?
    /// Where `capturedAt` came from (CaptureSource); empty when unknown.
    var captureSourceRaw: String = ""

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
