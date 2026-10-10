//
//  DocumentDraftTests.swift
//  PlowRTests
//

import Testing
import Foundation
import SwiftData
@testable import PlowR

/// The builder's pricing. The bug these pin: its estimate left out tax and
/// custom lines, and a cleared amount was saved without the after-hours
/// multiplier shown beside it.
struct DocumentDraftTests {

    private let mowing = DocumentDraft.Service(id: "mow", name: "Mowing", unitType: "perSqFt", pricePerUnit: 0.08)
    private let edging = DocumentDraft.Service(id: "edge", name: "Edging", unitType: "flat", pricePerUnit: 45)

    private func draft(multiplier: Double = 1.5) -> DocumentDraft {
        DocumentDraft(services: [mowing, edging],
                      zones: [.init(label: "Front", areaSquareFeet: 1_000), .init(label: "Back", areaSquareFeet: 500)],
                      afterHoursMultiplier: multiplier)
    }

    @Test func theDefaultIncludesTheAfterHoursMultiplier() {
        let d = draft()
        #expect(d.defaultAmount(serviceID: "mow", zoneIndex: 0) == 120)      // 1,000 × 0.08 × 1.5
        #expect(d.defaultAmount(serviceID: "edge", zoneIndex: -1) == 67.5)   // 45 × 1.5
        #expect(d.defaultAmount(serviceID: "none", zoneIndex: 0) == nil)
    }

    // A per-square-foot service for a client with no measured zones starts
    // at nothing, not at the rate: $0.08 for the whole property.
    @Test func aPerSquareFootServiceWithNoAreaStartsAtNothing() {
        let d = DocumentDraft(services: [mowing, edging], zones: [], afterHoursMultiplier: 1)
        #expect(d.defaultAmount(serviceID: "mow", zoneIndex: -1) == 0)
        #expect(d.defaultAmount(serviceID: "edge", zoneIndex: -1) == 45)
        // A zone drawn but not measured prices at nothing too.
        let unmeasured = DocumentDraft(services: [mowing], zones: [.init(label: "Front", areaSquareFeet: 0)],
                                       afterHoursMultiplier: 1)
        #expect(unmeasured.defaultAmount(serviceID: "mow", zoneIndex: 0) == 0)
    }

    // A cleared field bills the default shown beside it, multiplier included.
    @Test func aClearedAmountBillsTheDefaultShown() {
        var d = draft()
        let key = DocumentDraft.key(serviceID: "mow", zoneIndex: 1)
        d.selections = [key]
        d.amounts[key] = ""
        #expect(d.amount(forKey: key) == 60)                                  // 500 × 0.08 × 1.5
        d.amounts[key] = "75"
        #expect(d.amount(forKey: key) == 75)
    }

    @Test func customLinesNeedANameAndAPositiveAmount() {
        var d = draft()
        d.customLines = [.init(name: "Haul away", amount: "40"), .init(name: "", amount: "25"),
                         .init(name: "Free check", amount: "0")]
        #expect(d.lines().map(\.serviceName) == ["Haul away"])
    }

    // The estimate is the total of the document the draft makes: every kind of
    // line, the discount, the tax.
    @Test func theEstimateCountsTaxAndCustomLines() {
        var d = draft()
        let front = DocumentDraft.key(serviceID: "mow", zoneIndex: 0)
        d.selections = [front]
        d.amounts[front] = "100"
        d.customLines = [.init(name: "Haul away", amount: "50")]
        d.discount = "10"
        d.taxRate = "8"
        // (100 + 50 − 10) × 1.08 = 151.20. The old estimate showed 90.
        #expect(d.total == 151.2)
    }
}

/// The estimate and the saved document, priced by the step the builder uses.
@MainActor
struct DocumentDraftSaveTests {

    @Test(arguments: [false, true])
    func theSavedDocumentTotalsWhatTheEstimateSaid(grouped: Bool) throws {
        let container = try ModelContainer(
            for: Proposal.self, ProposalLineItem.self, Client.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        let context = container.mainContext
        var d = DocumentDraft(
            services: [.init(id: "mow", name: "Mowing", unitType: "perSqFt", pricePerUnit: 0.08),
                       .init(id: "edge", name: "Edging", unitType: "flat", pricePerUnit: 45)],
            zones: [.init(label: "Front", areaSquareFeet: 1_234.5), .init(label: "Back", areaSquareFeet: 500)],
            afterHoursMultiplier: 1.5)
        let front = DocumentDraft.key(serviceID: "mow", zoneIndex: 0)
        let back = DocumentDraft.key(serviceID: "mow", zoneIndex: 1)
        let edge = DocumentDraft.key(serviceID: "edge", zoneIndex: -1)
        d.selections = [front, back, edge]
        d.amounts = [front: "150.255", back: "", edge: "abc"]                 // typed, cleared, unreadable
        d.customLines = [.init(name: "Haul away", amount: "33.3"), .init(name: "", amount: "9")]
        d.discount = "12.5"
        d.taxRate = "8.875"

        let client = Client(name: "Pat", phone: "", address: "", operatorID: "op")
        context.insert(client)
        let doc = Proposal(operatorID: "op", client: client)
        d.apply(to: doc, grouped: grouped)
        // Saved as the builder saves it: the items first, then the document.
        let items = doc.lineItems ?? []
        items.forEach { context.insert($0) }
        doc.lineItems = items
        context.insert(doc)

        // Mowing twice, Edging, Haul away; grouped, Mowing becomes one line.
        #expect(items.count == (grouped ? 3 : 4))
        #expect(InvoiceLines.cents(doc.total) == InvoiceLines.cents(d.total))
        #expect(d.total > 0)
    }
}
