//
//  InvoiceLinesTests.swift
//  PlowRTests
//

import Testing
import Foundation
import SwiftData
@testable import PlowR

/// How a service recorded at a stop is billed. The bug these pin: a client with
/// two mapped zones was billed the whole-property price on each zone's line.
struct InvoiceLinesTests {

    private typealias Zone = InvoiceLines.Zone

    private let twoEqualZones = [Zone(label: "Driveway", areaSquareFeet: 1_000),
                                 Zone(label: "Walkway", areaSquareFeet: 1_000)]

    /// As Record Services saves: from the price field's text (nil if never shown).
    private func recorded(_ zones: [Zone], rate: Double = 0.08, unitType: String = "perSqFt",
                          typed: String?) -> [InvoiceLines.Line] {
        InvoiceLines.lines(serviceName: "Mowing", unitType: unitType, pricePerUnit: rate,
                           zones: zones, typedPrice: typed)
    }

    private func priced(_ zones: [Zone], price: Double) -> [InvoiceLines.Line] {
        InvoiceLines.lines(serviceName: "Mowing", unitType: "perSqFt", pricePerUnit: 0.08,
                           zones: zones, price: price)
    }

    private func total(_ lines: [InvoiceLines.Line]) -> Double {
        lines.reduce(0) { $0 + $1.lineTotal }
    }

    @Test func propertyPriceIsRateTimesTotalAreaToTheCent() {
        let zones = [Zone(label: "Front", areaSquareFeet: 1_000), Zone(label: "Back", areaSquareFeet: 500)]
        #expect(InvoiceLines.propertyPrice(unitType: "perSqFt", pricePerUnit: 0.08, zones: zones) == 120)
        #expect(InvoiceLines.propertyPrice(unitType: "flat", pricePerUnit: 45, zones: zones) == 45)
        #expect(InvoiceLines.propertyPrice(unitType: "perSqFt", pricePerUnit: 0.08, zones: []) == 0.08)
    }

    // The overcharge: 2 × 1,000 sq ft at $0.08 is $160 in total, not $160 per zone.
    @Test func twoZonesShareThePropertyPriceInsteadOfEachChargingIt() {
        let result = recorded(twoEqualZones, typed: nil)
        #expect(result.map(\.lineTotal) == [80, 80])
        #expect(result.map(\.zoneLabel) == ["Driveway", "Walkway"])
        #expect(total(result) == 160)
    }

    // The field shows the price with two decimals. Billing must land on the same
    // cent. $0.015 × 2,511 sq ft is 37.665: shown as 37.66 but billed 37.67 when
    // the two sides rounded differently (a stop reopened from the recap, where
    // the field shows the default without being typed in).
    @Test func thePriceShownIsThePriceBilled() {
        let zones = [Zone(label: "Front", areaSquareFeet: 1_255.5), Zone(label: "Back", areaSquareFeet: 1_255.5)]
        let shown = String(format: "%.2f",
                           InvoiceLines.propertyPrice(unitType: "perSqFt", pricePerUnit: 0.015, zones: zones))
        let untouched = recorded(zones, rate: 0.015, typed: nil)
        let retyped = recorded(zones, rate: 0.015, typed: shown)
        #expect(String(format: "%.2f", total(untouched)) == shown)
        #expect(String(format: "%.2f", total(retyped)) == shown)
    }

    // An untouched, cleared or unreadable field bills the whole-property default,
    // never the per-square-foot rate: 2 × $0.04 was the old fallback's bill.
    @Test func anEmptyOrUnreadablePriceBillsTheDefault() {
        for typed in [nil, "", "   ", "abc", "12..5", "nan", "inf", "-inf", "1e20"] as [String?] {
            #expect(recorded(twoEqualZones, typed: typed).map(\.lineTotal) == [80, 80], "typed: \(typed ?? "nil")")
        }
    }

    @Test func aTypedPriceIsSplitInProportionToArea() {
        let uneven = [Zone(label: "Front", areaSquareFeet: 1_000), Zone(label: "Back", areaSquareFeet: 500)]
        #expect(recorded(uneven, typed: "90").map(\.lineTotal) == [60, 30])
        #expect(recorded(uneven, typed: " 90.004 ").map(\.lineTotal) == [60, 30])
    }

    // What the PDF prints, row by row, must add up to what it prints as the total.
    @Test func sharesAlwaysAddUpToThePriceToTheCent() {
        let thirds = priced([Zone(label: "A", areaSquareFeet: 1),
                             Zone(label: "B", areaSquareFeet: 1),
                             Zone(label: "C", areaSquareFeet: 1)], price: 100)
        #expect(thirds.map(\.lineTotal) == [33.34, 33.33, 33.33])
        #expect(total(thirds) == 100)

        let uneven = priced([Zone(label: "A", areaSquareFeet: 1_234.5),
                             Zone(label: "B", areaSquareFeet: 87.25),
                             Zone(label: "C", areaSquareFeet: 402)], price: 137.99)
        #expect(abs(total(uneven) - 137.99) < 1e-9)
        for line in uneven {
            let exact = 137.99 * line.quantity / (1_234.5 + 87.25 + 402)
            #expect(abs(line.lineTotal - exact) <= 0.01)
        }
    }

    // Double(_:) accepts "inf", "nan" and 1e20; converting those to whole cents
    // would stop the app on Save Invoice.
    @Test func absurdAmountsNeverCrash() {
        #expect(InvoiceLines.split(.infinity, byWeights: [1, 1]) == [0, 0])
        #expect(InvoiceLines.split(.nan, byWeights: [1]) == [0])
        #expect(InvoiceLines.split(1e17, byWeights: [1]) == [0])
        #expect(InvoiceLines.cents(-.infinity) == 0)
        #expect(total(priced(twoEqualZones, price: 1e300)) == 0)
    }

    @Test func oneZoneIsBilledTheWholePrice() {
        let result = recorded([Zone(label: "Lot", areaSquareFeet: 1_234.5)], typed: nil)
        #expect(result.count == 1)
        #expect(result.first?.lineTotal == 98.76)
        #expect(result.first?.quantity == 1_234.5)
    }

    @Test func leftAloneTheCatalogRateStandsAndChangedItBecomesTheNewRate() {
        #expect(recorded(twoEqualZones, typed: nil).allSatisfy { $0.unitPrice == 0.08 })
        #expect(recorded(twoEqualZones, typed: "160.00").allSatisfy { $0.unitPrice == 0.08 })
        #expect(recorded(twoEqualZones, typed: "200").allSatisfy { abs($0.unitPrice - 0.1) < 1e-12 })
    }

    @Test func aFlatServiceIsOneLineAtItsPrice() {
        let result = recorded([Zone(label: "Front", areaSquareFeet: 1_000)], rate: 45, unitType: "flat", typed: "50")
        #expect(result.count == 1)
        #expect(result.first?.lineTotal == 50)
        #expect(result.first?.unitType == "flat")
        #expect(result.first?.zoneLabel == "All Zones")
    }

    // No mapped area: nothing to split by, so the price is billed once.
    @Test func withoutMappedAreaAPerSquareFootServiceIsOneLine() {
        let unmapped = recorded([], typed: "75")
        #expect(unmapped.map(\.lineTotal) == [75])
        #expect(unmapped.first?.zoneLabel == "Property")

        let emptyZones = recorded([Zone(label: "Sketch", areaSquareFeet: 0)], typed: "75")
        #expect(emptyZones.map(\.lineTotal) == [75])
        #expect(emptyZones.first?.zoneLabel == "All Zones")
    }
}

/// Grouping and copying must keep every line's amount.
@MainActor
struct InvoiceLineAmountTests {

    private func item(_ name: String, total: Double, unitType: String = "flat",
                      quantity: Double = 1, sortOrder: Int) -> ProposalLineItem {
        let item = ProposalLineItem(serviceName: name, zoneLabel: "Zone", quantity: quantity,
                                    unitType: unitType, unitPrice: unitType == "flat" ? total : 0.08,
                                    sortOrder: sortOrder)
        item.lineTotal = total
        return item
    }

    // Two flat "Edging" lines used to merge into one line at a single price.
    @Test func groupingAddsUpTheLinesItMerges() {
        let merged = ProposalLineItem.grouped([
            item("Edging", total: 30, sortOrder: 0),
            item("Mowing", total: 64.5, unitType: "perSqFt", quantity: 800, sortOrder: 1),
            item("Edging", total: 35, sortOrder: 2),
            item("Mowing", total: 40, unitType: "perSqFt", quantity: 500, sortOrder: 3),
        ])
        #expect(merged.map(\.serviceName) == ["Edging", "Mowing"])
        #expect(merged.map(\.lineTotal) == [65, 104.5])
        #expect(merged.last?.quantity == 1_300)
    }

    // A group sits where its first line did. The input is deliberately out of
    // order, so "first line", "last line" and "as given" all give different answers.
    @Test func aGroupTakesItsFirstLinesPlace() {
        let merged = ProposalLineItem.grouped([
            item("B", total: 1, sortOrder: 1),
            item("A", total: 1, sortOrder: 0),
            item("C", total: 1, sortOrder: 4),
            item("A", total: 1, sortOrder: 3),
            item("B", total: 1, sortOrder: 2),
        ])
        #expect(merged.map(\.serviceName) == ["A", "B", "C"])
        #expect(merged.map(\.sortOrder) == [0, 1, 4])
    }

    @Test func aLineWithNoTwinIsLeftAsItIs() {
        let only = item("Mulching", total: 212.4, unitType: "perSqFt", quantity: 1_770, sortOrder: 0)
        let merged = ProposalLineItem.grouped([only])
        #expect(merged.count == 1)
        #expect(merged.first === only)
    }

    // A revision or a duplicate must bill what the original billed, including
    // amounts typed over the catalog price.
    @Test func copiesKeepEachLinesAmount() throws {
        let container = try ModelContainer(
            for: Proposal.self, ProposalLineItem.self, Client.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        let context = container.mainContext
        let client = Client(name: "Pat", phone: "", address: "1 Main St", operatorID: "op")
        context.insert(client)
        let proposal = Proposal(operatorID: "op", client: client)
        let typed = item("Hedge Trimming", total: 85, sortOrder: 0)          // catalog price 85, typed over below
        typed.lineTotal = 110
        let zoneShare = item("Mowing", total: 80, unitType: "perSqFt", quantity: 1_000, sortOrder: 1)
        [typed, zoneShare].forEach { context.insert($0) }
        proposal.lineItems = [typed, zoneShare]
        context.insert(proposal)

        let copies = proposal.makeLineItemCopies().sorted { $0.sortOrder < $1.sortOrder }
        #expect(copies.map(\.lineTotal) == [110, 80])
    }
}
