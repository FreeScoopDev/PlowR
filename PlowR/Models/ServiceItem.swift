import Foundation
import SwiftData

@Model
final class ServiceItem {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = "custom"   // "snow", "lawn", "cleanup", "custom"
    var unitType: String = "flat"     // "flat", "perSqFt"
    var pricePerUnit: Double = 0.0
    var unitLabel: String = ""  // e.g. "bag", "hr", "ton" — used when unitType == "perUnit"
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

    /// The starter catalog a business can add by category (ServiceCatalog.
    /// addStandard). Every one is flat, at a placeholder price the business
    /// edits in its catalog: five used to be per square foot, so a business
    /// that hadn't measured its clients' areas recorded them at $0 (Joe,
    /// 2026-11-10). Per square foot stays a choice in Add Service. Catalogs
    /// made before keep what they have.
    static let defaultServices: [(name: String, category: String, unitType: String, price: Double)] = [
        ("Snow Plowing",         "snow",    "flat",    50.0),
        ("Salting / Ice Melt",   "snow",    "flat",    25.0),
        ("Walkway Shoveling",    "snow",    "flat",    45.0),
        ("Roof Snow Removal",    "snow",    "flat",    150.0),
        ("Lawn Mowing",          "lawn",    "flat",    45.0),
        ("Edging",               "lawn",    "flat",    30.0),
        ("Fertilization",        "lawn",    "flat",    60.0),
        ("Hedge Trimming",       "lawn",    "flat",    60.0),
        ("Spring Cleanup",       "cleanup", "flat",    120.0),
        ("Fall Cleanup",         "cleanup", "flat",    120.0),
        ("Mulching",             "cleanup", "flat",    75.0),
    ]
}
