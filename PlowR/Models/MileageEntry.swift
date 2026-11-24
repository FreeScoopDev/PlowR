import Foundation
import SwiftData

/// A trip driven for the business, typed by the user: how far, and what for.
/// PlowR doesn't measure it (no odometer, no GPS distance): linking a route
/// only names it.
///
/// Like Expense, it refers to a client and a route by ID with a copy of
/// their names, with no relationship, so it outlives either. Every field has
/// a default and none is unique, as CloudKit needs.
@Model
final class MileageEntry {
    var id: UUID = UUID()
    var operatorID: String = ""
    var date: Date = Date()
    /// In `unitRaw`'s unit, as typed.
    var distance: Double = 0
    /// "mi" or "km" (DistanceUnit), whichever the entry was typed in.
    var unitRaw: String = "mi"
    /// What the trip was for ("Supply run").
    var purpose: String = ""
    var routeID: String = ""
    var routeName: String = ""
    var clientID: String = ""
    var clientName: String = ""
    var note: String = ""
    var createdAt: Date = Date()

    init(operatorID: String, date: Date = Date(), distance: Double = 0, unit: DistanceUnit = .miles, purpose: String = "") {
        self.operatorID = operatorID
        self.date = date
        self.distance = distance
        self.unitRaw = unit.rawValue
        self.purpose = purpose
    }

    /// The unit; one this build doesn't know reads as miles.
    var unit: DistanceUnit {
        get { DistanceUnit(rawValue: unitRaw) ?? .miles }
        set { unitRaw = newValue.rawValue }
    }
}
