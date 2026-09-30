import Foundation

/// What Record Services has on screen for a stop, priced the one way that
/// both the Service Log record and the invoice use.
///
/// The sheet used to price only the invoice, and saved nothing but the
/// services' IDs on the stop: the log re-priced them from the catalog and
/// left out custom items, so it disagreed with the invoice whenever the
/// driver typed a price.
///
/// `nonisolated`: plain values and arithmetic, used from the view and from tests.
nonisolated struct StopRecording {

    struct Service {
        var id: String
        var name: String
        var unitType: String
        var pricePerUnit: Double
    }

    struct CustomItem {
        var name: String
        var price: String
    }

    /// The catalog's services, in its order.
    var services: [Service]
    var zones: [InvoiceLines.Zone]
    var selectedIDs: Set<String> = []
    /// Prices typed per service ID.
    var typedPrices: [String: String] = [:]
    var customItems: [CustomItem] = []
    /// Lines already recorded for services no longer in the active catalog
    /// (switched off or deleted): kept as they were, since the sheet can't
    /// show them as services to tick.
    var keptLines: [ServiceRecord.Line] = []

    /// The invoice's lines: each selected service's whole-property figure (or
    /// the typed price), split across zones as InvoiceLines does, then the
    /// custom items with a name and a price above zero.
    var invoiceLines: [InvoiceLines.Line] {
        var lines: [InvoiceLines.Line] = []
        for service in services where selectedIDs.contains(service.id) {
            lines += InvoiceLines.lines(serviceName: service.name, unitType: service.unitType,
                                        pricePerUnit: service.pricePerUnit, zones: zones,
                                        typedPrice: typedPrices[service.id])
        }
        for kept in keptLines {
            lines.append(InvoiceLines.Line(serviceName: kept.name, zoneLabel: "", quantity: 1,
                                           unitType: "flat", unitPrice: kept.price, lineTotal: kept.price))
        }
        for custom in pricedCustomItems {
            lines.append(InvoiceLines.Line(serviceName: custom.name, zoneLabel: "", quantity: 1,
                                           unitType: "flat", unitPrice: custom.price, lineTotal: custom.price))
        }
        return lines
    }

    /// The Service Log's lines: one per service, priced at what its invoice
    /// lines add up to, then the custom items. Same total as the invoice.
    var recordLines: [ServiceRecord.Line] {
        var lines: [ServiceRecord.Line] = []
        for service in services where selectedIDs.contains(service.id) {
            let split = InvoiceLines.lines(serviceName: service.name, unitType: service.unitType,
                                           pricePerUnit: service.pricePerUnit, zones: zones,
                                           typedPrice: typedPrices[service.id])
            let total = InvoiceLines.roundedToCent(split.reduce(0) { $0 + $1.lineTotal })
            lines.append(ServiceRecord.Line(serviceID: service.id, name: service.name,
                                            unitType: service.unitType, price: total))
        }
        lines += keptLines
        for custom in pricedCustomItems {
            lines.append(ServiceRecord.Line(serviceID: "", name: custom.name, unitType: "flat", price: custom.price))
        }
        return lines
    }

    /// The sheet for a record's `lines`: each catalog service on it selected
    /// at its recorded price, custom items as custom items, and any other
    /// service kept as it is. Reopening and saving then changes nothing.
    static func loading(_ lines: [ServiceRecord.Line], services: [Service], zones: [InvoiceLines.Zone]) -> StopRecording {
        let shown = Set(services.map(\.id))
        var recording = StopRecording(services: services, zones: zones)
        for line in lines {
            if line.serviceID.isEmpty {
                recording.customItems.append(CustomItem(name: line.name, price: money(line.price)))
            } else if shown.contains(line.serviceID) {
                recording.selectedIDs.insert(line.serviceID)
                recording.typedPrices[line.serviceID] = money(line.price)
            } else {
                recording.keptLines.append(line)
            }
        }
        return recording
    }

    /// An amount as a price field shows it.
    static func money(_ amount: Double) -> String { String(format: "%.2f", amount) }

    /// Custom items that go on the bill: named, with a readable price above zero.
    private var pricedCustomItems: [(name: String, price: Double)] {
        customItems.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespaces)
            let price = InvoiceLines.price(typed: item.price, default: 0)
            return name.isEmpty || price <= 0 ? nil : (name, price)
        }
    }
}
