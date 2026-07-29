import Foundation
import SwiftData

@Model
final class ProposalLineItem {
    var id: UUID = UUID()
    var serviceName: String = ""
    var zoneLabel: String = ""
    var quantity: Double = 0.0      // sqft for perSqFt, 1.0 for flat
    var unitType: String = "flat"   // "flat" or "perSqFt"
    var unitPrice: Double = 0.0
    var lineTotal: Double = 0.0
    var sortOrder: Int = 0
    var itemNotes: String = ""
    var proposal: Proposal?

    init(serviceName: String, zoneLabel: String, quantity: Double,
         unitType: String, unitPrice: Double, sortOrder: Int = 0, itemNotes: String = "") {
        self.serviceName = serviceName
        self.zoneLabel = zoneLabel
        self.quantity = quantity
        self.unitType = unitType
        self.unitPrice = unitPrice
        self.sortOrder = sortOrder
        self.lineTotal = unitType == "flat" ? unitPrice : quantity * unitPrice
        self.itemNotes = itemNotes
    }
}
