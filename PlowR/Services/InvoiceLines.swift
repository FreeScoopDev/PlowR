import Foundation

/// How one service recorded at a stop becomes invoice lines.
///
/// A per-square-foot service on a client with mapped zones is priced for the
/// whole property: rate × total mapped area. That is the one figure the driver
/// sees in Record Services, and may change. It becomes one line per zone, and
/// the zone lines always add up to that figure. They used to repeat it: every
/// zone line carried the whole-property price, so a client with two zones was
/// billed twice and one with three zones three times.
///
/// `nonisolated` because this is plain arithmetic, used from a view and from
/// tests; the app target defaults everything to @MainActor.
nonisolated enum InvoiceLines {

    struct Zone: Equatable {
        var label: String
        var areaSquareFeet: Double
    }

    struct Line: Equatable {
        var serviceName: String
        var zoneLabel: String
        var quantity: Double
        var unitType: String
        var unitPrice: Double
        var lineTotal: Double
    }

    /// The price of a service for the whole property: rate × total mapped area
    /// for a per-square-foot service, otherwise the service's own price.
    static func propertyPrice(unitType: String, pricePerUnit: Double, zones: [Zone]) -> Double {
        let area = totalArea(zones)
        guard unitType == "perSqFt", area > 0 else { return pricePerUnit }
        return pricePerUnit * area
    }

    /// The invoice lines for one service, priced at `price` for the whole
    /// property. The lines' totals add up to `price`, rounded to the cent.
    static func lines(serviceName: String, unitType: String, pricePerUnit: Double,
                      zones: [Zone], price: Double) -> [Line] {
        let area = totalArea(zones)
        guard unitType == "perSqFt", area > 0 else {
            // A flat service, or a client with no mapped area: one line.
            return [Line(serviceName: serviceName,
                         zoneLabel: zones.isEmpty ? "Property" : "All Zones",
                         quantity: 1, unitType: "flat",
                         unitPrice: price, lineTotal: price)]
        }
        // Left alone, the catalog rate stands. Changed, the driver's figure is
        // the new price for the whole property, which is a new rate.
        let isCatalogPrice = abs(price - pricePerUnit * area) < 0.005
        let rate = isCatalogPrice ? pricePerUnit : price / area
        let totals = split(price, byWeights: zones.map { max(0, $0.areaSquareFeet) })
        return zip(zones, totals).map { zone, total in
            Line(serviceName: serviceName, zoneLabel: zone.label,
                 quantity: zone.areaSquareFeet, unitType: unitType,
                 unitPrice: rate, lineTotal: total)
        }
    }

    /// Splits `amount` into whole cents in proportion to `weights`. The shares
    /// add up to `amount` rounded to the cent, and each is within a cent of its
    /// exact share: every share is rounded down, then the cents left over go
    /// to the shares that lost the most (earlier ones first on a tie).
    static func split(_ amount: Double, byWeights weights: [Double]) -> [Double] {
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return weights.map { _ in 0 } }
        let totalCents = Int((amount * 100).rounded())
        let exact = weights.map { Double(totalCents) * $0 / totalWeight }
        var cents = exact.map { Int($0.rounded(.down)) }
        var left = totalCents - cents.reduce(0, +)
        let byRemainder = exact.indices.sorted { a, b in
            let ra = exact[a] - Double(cents[a]), rb = exact[b] - Double(cents[b])
            return ra != rb ? ra > rb : a < b
        }
        for i in byRemainder where left > 0 {
            cents[i] += 1
            left -= 1
        }
        return cents.map { Double($0) / 100 }
    }

    private static func totalArea(_ zones: [Zone]) -> Double {
        zones.reduce(0) { $0 + max(0, $1.areaSquareFeet) }
    }
}
