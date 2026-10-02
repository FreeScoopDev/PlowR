import Foundation
import SwiftData

/// A day a client's place didn't reach their contract's snow trigger: the
/// forecast said a storm, but not enough fell there to clear. Checked at the
/// stop on a route ("Below Trigger"), or marked by hand (the storm card, the
/// contract's page). The Service Report lists them, said for which: a check
/// at the stop is PlowR's record of being there; a mark by hand isn't.
@Model
final class TriggerCheck {
    var id: UUID = UUID()
    var operatorID: String = ""
    var clientID: String = ""
    /// A copy of the client's name when it was made.
    var clientName: String = ""
    /// The place (Place.id) it's for.
    var placeID: String = ""
    /// The day it's for, at its start.
    var day: Date = Date()
    /// When it was checked or marked.
    var checkedAt: Date = Date()
    /// "stop": checked at the stop on a route. "marked": by hand.
    var sourceRaw: String = "marked"
    /// For a check at a stop: the run and stop, and the GPS arrival if caught.
    var runID: String = ""
    var stopID: String = ""
    var routeName: String = ""
    var arrivedAt: Date?
    var note: String = ""
    var createdAt: Date = Date()

    init(operatorID: String, clientID: String, clientName: String, placeID: String, day: Date) {
        self.operatorID = operatorID
        self.clientID = clientID
        self.clientName = clientName
        self.placeID = placeID
        self.day = day
    }

    var isFromStop: Bool { sourceRaw == "stop" }
}
