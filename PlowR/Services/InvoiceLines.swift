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
/// Money is rounded to the cent in one place, `cents(_:)`, so the price a
/// screen shows and the price an invoice bills can't round differently.
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

    /// Beyond any real job. A typed figure this large is treated as unreadable.
    static let maxAmount = 1_000_000_000.0

    /// `amount` in whole cents, rounded half away from zero. The one rounding
    /// rule for money here. Never traps: a non-finite or absurd amount is 0.
    static func cents(_ amount: Double) -> Int {
        guard amount.isFinite, abs(amount) < maxAmount else { return 0 }
        return Int((amount * 100).rounded())
    }

    static func roundedToCent(_ amount: Double) -> Double {
        Double(cents(amount)) / 100
    }

    static func totalArea(_ zones: [Zone]) -> Double {
        zones.reduce(0) { $0 + max(0, $1.areaSquareFeet) }
    }

    /// The price of a service for the whole property, to the cent: rate × total
    /// mapped area for a per-square-foot service, otherwise the service's own
    /// price, times `multiplier` (an after-hours visit's). This is what Record
    /// Services shows in the price field, and what the Service Log records.
    static func propertyPrice(unitType: String, pricePerUnit: Double, zones: [Zone],
                              multiplier: Double = 1) -> Double {
        let area = totalArea(zones)
        let base = unitType == "perSqFt" && area > 0 ? pricePerUnit * area : pricePerUnit
        return roundedToCent(base * multiplier)
    }

    /// The price field's text as money, or `defaultPrice` when the field is
    /// empty, unreadable or not a real amount: an untouched field means the
    /// default, never the per-square-foot rate. A decimal comma ("12,50") is
    /// read where the region writes one (`DecimalText`).
    static func price(typed: String?, default defaultPrice: Double, locale: Locale = .current) -> Double {
        guard let value = DecimalText.number(typed, locale: locale), abs(value) < maxAmount else { return defaultPrice }
        return roundedToCent(value)
    }

    /// The invoice lines for a service as recorded at a stop, from what's in
    /// its price field (nil if the field was never shown).
    static func lines(serviceName: String, unitType: String, pricePerUnit: Double,
                      zones: [Zone], typedPrice: String?) -> [Line] {
        let whole = propertyPrice(unitType: unitType, pricePerUnit: pricePerUnit, zones: zones)
        return lines(serviceName: serviceName, unitType: unitType, pricePerUnit: pricePerUnit,
                     zones: zones, price: price(typed: typedPrice, default: whole))
    }

    /// The invoice lines for one service, priced at `price` for the whole
    /// property. The lines' totals add up to `price`, to the cent.
    static func lines(serviceName: String, unitType: String, pricePerUnit: Double,
                      zones: [Zone], price: Double) -> [Line] {
        let area = totalArea(zones)
        guard unitType == "perSqFt", area > 0 else {
            // A flat service, or a client with no mapped area: one line.
            let total = roundedToCent(price)
            return [Line(serviceName: serviceName,
                         zoneLabel: zones.isEmpty ? "Property" : "All Zones",
                         quantity: 1, unitType: "flat",
                         unitPrice: total, lineTotal: total)]
        }
        // Left alone, the catalog rate stands. Changed, the driver's figure is
        // the new price for the whole property, which is a new rate.
        let isCatalogPrice = cents(price) == cents(pricePerUnit * area)
        let rate = isCatalogPrice ? pricePerUnit : price / area
        let totals = split(price, byWeights: zones.map { max(0, $0.areaSquareFeet) })
        return zip(zones, totals).map { zone, total in
            Line(serviceName: serviceName, zoneLabel: zone.label,
                 quantity: max(0, zone.areaSquareFeet), unitType: unitType,
                 unitPrice: rate, lineTotal: total)
        }
    }

    /// Splits `amount` into whole cents in proportion to `weights`. The shares
    /// add up to `amount` in cents, and each is within a cent of its exact
    /// share: every share is rounded down, then the cents left over go to the
    /// shares that lost the most (earlier ones first on a tie).
    static func split(_ amount: Double, byWeights weights: [Double]) -> [Double] {
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0, totalWeight.isFinite else { return weights.map { _ in 0 } }
        let totalCents = cents(amount)
        let exact = weights.map { Double(totalCents) * $0 / totalWeight }
        var shares = exact.map { Int($0.rounded(.down)) }
        var left = totalCents - shares.reduce(0, +)
        let byRemainder = exact.indices.sorted { a, b in
            let ra = exact[a] - Double(shares[a]), rb = exact[b] - Double(shares[b])
            return ra != rb ? ra > rb : a < b
        }
        for i in byRemainder where left > 0 {
            shares[i] += 1
            left -= 1
        }
        return shares.map { Double($0) / 100 }
    }
}
