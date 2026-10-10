import Foundation

/// A proposal or invoice being put together on the builder screen, priced the
/// one way that both the screen's estimate and the saved document use.
///
/// The estimate and the saved lines used to be worked out separately inside the
/// view: the estimate left out tax and custom lines, and a cleared amount was
/// saved without the after-hours multiplier shown beside it. Keeping the pricing
/// here, as plain values, means the two can't drift apart unnoticed: a test
/// builds a document from a draft and checks its total against the estimate.
///
/// `nonisolated`: plain values and arithmetic, used from the view and from tests.
nonisolated struct DocumentDraft {

    /// The Tax field's starting text on a new document: the business's own
    /// sales tax (Business Profile), or empty when it has none.
    static func startingTaxText(rate: Double?) -> String {
        guard let rate, rate > 0 else { return "" }
        return Proposal.percentText(rate)
    }

    struct Service {
        var id: String
        var name: String
        var unitType: String
        var pricePerUnit: Double
    }

    struct Zone {
        var label: String
        var areaSquareFeet: Double
    }

    struct CustomLine {
        var name: String
        var amount: String
        var notes: String = ""
    }

    struct Line: Equatable {
        var serviceName: String
        var zoneLabel: String
        var quantity: Double
        var unitType: String
        var unitPrice: Double
        var lineTotal: Double
        var notes: String
        var sortOrder: Int
    }

    var services: [Service]
    var zones: [Zone]
    var afterHoursMultiplier: Double = 1
    /// Selected lines, keyed "serviceID|zoneIndex" (zone index -1: the whole property).
    var selections: Set<String> = []
    /// Amounts typed per key.
    var amounts: [String: String] = [:]
    var lineNotes: [String: String] = [:]
    var customLines: [CustomLine] = []
    var discount: String = ""
    var taxRate: String = ""
    /// Whose decimal separator the fields are typed in (`DecimalText`).
    var locale: Locale = .current

    static func key(serviceID: String, zoneIndex: Int) -> String { "\(serviceID)|\(zoneIndex)" }

    /// What a line costs before anything is typed, to the cent: area × rate for
    /// a zone, the service's price for the whole property, times the after-hours
    /// multiplier. Shown beside the field, pre-filled into it, and used when it's
    /// cleared, all from here.
    func defaultAmount(serviceID: String, zoneIndex: Int) -> Double? {
        guard let service = services.first(where: { $0.id == serviceID }) else { return nil }
        let base = zones.indices.contains(zoneIndex)
            ? zones[zoneIndex].areaSquareFeet * service.pricePerUnit
            : service.pricePerUnit
        return InvoiceLines.roundedToCent(base * afterHoursMultiplier)
    }

    /// A selected line's amount: what's typed, or the default if the field is empty or unreadable.
    func amount(forKey key: String) -> Double? {
        guard let (serviceID, zoneIndex) = Self.parse(key),
              let fallback = defaultAmount(serviceID: serviceID, zoneIndex: zoneIndex) else { return nil }
        return InvoiceLines.price(typed: amounts[key], default: fallback, locale: locale)
    }

    var discountAmount: Double { max(0, InvoiceLines.price(typed: discount, default: 0, locale: locale)) }
    var taxRatePercent: Double { Proposal.taxRate(typed: taxRate) }

    /// Every line the document will have, in the order it will have them:
    /// selected services (by key), then custom lines with a name and a positive amount.
    func lines() -> [Line] {
        var result: [Line] = []
        for key in selections.sorted() {
            guard let (serviceID, zoneIndex) = Self.parse(key),
                  let service = services.first(where: { $0.id == serviceID }),
                  let amount = amount(forKey: key) else { continue }
            let note = lineNotes[key] ?? ""
            if zones.indices.contains(zoneIndex) {
                let zone = zones[zoneIndex]
                result.append(Line(serviceName: service.name, zoneLabel: zone.label, quantity: zone.areaSquareFeet,
                                   unitType: service.unitType, unitPrice: service.pricePerUnit, lineTotal: amount,
                                   notes: note, sortOrder: result.count))
            } else {
                result.append(Line(serviceName: service.name, zoneLabel: "Property", quantity: 1,
                                   unitType: "flat", unitPrice: service.pricePerUnit, lineTotal: amount,
                                   notes: note, sortOrder: result.count))
            }
        }
        let firstCustom = result.count
        for (i, custom) in customLines.enumerated() {
            guard !custom.name.isEmpty else { continue }
            let amount = InvoiceLines.price(typed: custom.amount, default: 0, locale: locale)
            guard amount > 0 else { continue }
            result.append(Line(serviceName: custom.name, zoneLabel: "", quantity: 1, unitType: "flat",
                               unitPrice: amount, lineTotal: amount, notes: custom.notes,
                               sortOrder: firstCustom + i))
        }
        return result
    }

    /// The estimate: the total of the document these lines, discount and tax make.
    var total: Double {
        Proposal.totals(subtotal: lines().reduce(0) { $0 + $1.lineTotal },
                        discount: discountAmount, taxRate: taxRatePercent).total
    }

    private static func parse(_ key: String) -> (String, Int)? {
        let parts = key.split(separator: "|")
        guard parts.count == 2, let zoneIndex = Int(parts[1]) else { return nil }
        return (String(parts[0]), zoneIndex)
    }
}

extension DocumentDraft {
    /// Prices `proposal` from this draft: its discount, tax rate and line items,
    /// grouped by service if asked. The builder previews and saves exactly this,
    /// so the document's total is the estimate.
    @MainActor
    func apply(to proposal: Proposal, grouped: Bool) {
        proposal.discountAmount = discountAmount
        proposal.taxRate = taxRatePercent
        let items = makeLineItems()
        proposal.lineItems = grouped ? ProposalLineItem.grouped(items) : items
    }

    /// The draft's lines as line items for a document. Each keeps its amount.
    @MainActor
    func makeLineItems() -> [ProposalLineItem] {
        lines().map { line in
            let item = ProposalLineItem(serviceName: line.serviceName, zoneLabel: line.zoneLabel,
                                        quantity: line.quantity, unitType: line.unitType,
                                        unitPrice: line.unitPrice, sortOrder: line.sortOrder,
                                        itemNotes: line.notes)
            item.lineTotal = line.lineTotal
            return item
        }
    }
}
