import Foundation
import SwiftData

@Model
final class ServiceItem {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = "custom"   // "snow", "lawn", "cleanup", "custom"
    var unitType: String = "flat"     // "flat", "perSqFt"
    var pricePerUnit: Double = 0.0
    var isActive: Bool = true
    var isBuiltIn: Bool = false
    var operatorID: String = ""
    var sortOrder: Int = 0

    init(name: String, category: String, unitType: String, pricePerUnit: Double,
         isBuiltIn: Bool = false, operatorID: String, sortOrder: Int = 0) {
        self.name = name
        self.category = category
        self.unitType = unitType
        self.pricePerUnit = pricePerUnit
        self.isBuiltIn = isBuiltIn
        self.operatorID = operatorID
        self.sortOrder = sortOrder
    }

    static let defaultServices: [(name: String, category: String, unitType: String, price: Double)] = [
        ("Snow Plowing",         "snow",    "perSqFt", 0.08),
        ("Salting / Ice Melt",   "snow",    "perSqFt", 0.03),
        ("Walkway Shoveling",    "snow",    "flat",    45.0),
        ("Roof Snow Removal",    "snow",    "flat",    150.0),
        ("Lawn Mowing",          "lawn",    "perSqFt", 0.06),
        ("Edging",               "lawn",    "flat",    30.0),
        ("Fertilization",        "lawn",    "perSqFt", 0.04),
        ("Hedge Trimming",       "lawn",    "flat",    60.0),
        ("Spring Cleanup",       "cleanup", "flat",    120.0),
        ("Fall Cleanup",         "cleanup", "flat",    120.0),
        ("Mulching",             "cleanup", "perSqFt", 0.12),
    ]
}
