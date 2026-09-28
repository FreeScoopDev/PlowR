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

    /// One line per service name, for "Group line items by service". A merged
    /// line's total is the sum of the lines it replaces, so grouping never
    /// changes what the client owes. (It used to recompute the total from the
    /// last line's unit price, dropping typed amounts and, for two flat lines,
    /// one line's price entirely.)
    static func grouped(_ items: [ProposalLineItem]) -> [ProposalLineItem] {
        var order: [String] = []
        var byName: [String: [ProposalLineItem]] = [:]
        for item in items {
            if byName[item.serviceName] == nil { order.append(item.serviceName) }
            byName[item.serviceName, default: []].append(item)
        }
        return order.compactMap { name in
            guard let group = byName[name], let first = group.first else { return nil }
            guard group.count > 1 else { return first }
            let quantity = group.reduce(0) { $0 + $1.quantity }
            let total = group.reduce(0) { $0 + $1.lineTotal }
            let sameUnit = group.allSatisfy { $0.unitType == first.unitType }
            let unitType = sameUnit ? first.unitType : "flat"
            let unitPrice = unitType == "perSqFt" && quantity > 0 ? total / quantity : total
            let notes = group.map(\.itemNotes).filter { !$0.isEmpty }
            let merged = ProposalLineItem(
                serviceName: name,
                zoneLabel: "All Zones",
                quantity: unitType == "flat" ? 1 : quantity,
                unitType: unitType,
                unitPrice: unitPrice,
                sortOrder: first.sortOrder,
                itemNotes: notes.joined(separator: "; ")
            )
            merged.lineTotal = total
            return merged
        }
        .sorted { $0.sortOrder < $1.sortOrder }
    }
}
