import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A price, discount or tax rate that can't be read is pointed out, and the
/// document isn't saved with something else in its place (pre-launch money
/// review, 2026-10-18). Before, in a US region "1,250" quietly billed the
/// catalog price, a discount became $0, a custom line was dropped, and a tax
/// of "105" or "8..25" became 0%.
@MainActor
struct UnreadableAmountsTests {
    let us = Locale(identifier: "en_US")
    let germany = Locale(identifier: "de_DE")

    @Test func whatCountsAsUnreadable() {
        for readable in ["", " ", "0", "12", "12.50", " 1250.5 ", "999999999"] {
            #expect(!InvoiceLines.isUnreadable(readable, locale: us), "\(readable)")
        }
        #expect(!InvoiceLines.isUnreadable(nil, locale: us))
        for unreadable in ["1,250", "1,250.00", "8..25", "abc", "-5", "1e12", "nan", "$40"] {
            #expect(InvoiceLines.isUnreadable(unreadable, locale: us), "\(unreadable)")
        }
        // A decimal comma where the region writes one.
        #expect(!InvoiceLines.isUnreadable("12,50", locale: germany))
        #expect(InvoiceLines.isUnreadable("1.250,00", locale: germany))
    }

    private let edging = DocumentDraft.Service(id: "edge", name: "Edging", unitType: "flat", pricePerUnit: 45)
    private let mowing = DocumentDraft.Service(id: "mow", name: "Mowing", unitType: "perSqFt", pricePerUnit: 0.08)

    private func draft(amount: String? = nil, custom: String = "", discount: String = "", tax: String = "") -> DocumentDraft {
        var amounts: [String: String] = [:]
        if let amount { amounts["edge|-1"] = amount }
        return DocumentDraft(services: [edging, mowing], zones: [.init(label: "Front", areaSquareFeet: 1_000)],
                             selections: ["edge|-1", "mow|0"], amounts: amounts,
                             customLines: custom.isEmpty ? [] : [.init(name: "Haul away", amount: custom)],
                             discount: discount, taxRate: tax, locale: us)
    }

    @Test func theBuilderNamesWhatItCantRead() {
        #expect(draft().unreadableFields.isEmpty)
        #expect(draft(amount: "60", custom: "25", discount: "5", tax: "8.25").unreadableFields.isEmpty)
        #expect(draft(amount: "1,250").unreadableFields == ["Edging"])
        #expect(draft(custom: "1,250").unreadableFields == ["Haul away"])
        #expect(draft(discount: "1,250").unreadableFields == ["Discount"])
        #expect(draft(tax: "105").unreadableFields == ["Tax"])
        #expect(draft(tax: "8..25").unreadableFields == ["Tax"])
        #expect(draft(amount: "-60").unreadableFields == ["Edging"])
        var zoned = draft()
        zoned.amounts["mow|0"] = "eighty"
        #expect(zoned.unreadableFields == ["Mowing, Front"])
        #expect(draft(amount: "x", discount: "y", tax: "z").unreadableFields == ["Edging", "Discount", "Tax"])
    }

    @Test func theMessageSaysWhatToType() {
        #expect(DocumentDraft.unreadableMessage(["Edging"]) == "Can't read Edging: type a number such as 1250.50.")
        #expect(DocumentDraft.unreadableMessage(["Discount", "Tax"])
                == "Can't read Discount, Tax: type a number such as 1250.50 (a tax rate from 0 to 100).")
    }

    @Test func recordServicesNamesWhatItCantRead() {
        var recording = StopRecording(services: [StopRecording.Service(id: "plow", name: "Clearing", unitType: "flat",
                                                                       pricePerUnit: 60)], zones: [])
        recording.selectedIDs = ["plow"]
        #expect(recording.unreadableFields.isEmpty)
        recording.typedPrices["plow"] = "1,250"
        #expect(recording.unreadableFields == ["Clearing"])
        recording.selectedIDs = []                                                // not ticked: not billed
        #expect(recording.unreadableFields.isEmpty)
        recording.customItems = [.init(name: "Salt", price: "2O")]
        #expect(recording.unreadableFields == ["Salt"])
        recording.customItems = [.init(name: " ", price: "x")]
        #expect(recording.unreadableFields == ["A custom item"])
    }

    // The Edit screen: a field it can't read isn't saved, and the stored value stays.
    @Test func theEditScreenKeepsWhatItCantRead() throws {
        let container = try ModelContainer(
            for: Proposal.self, ProposalLineItem.self, Client.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        let context = container.mainContext
        let client = Client(name: "Pat Doe", phone: "", address: "", operatorID: "op")
        context.insert(client)
        let doc = Proposal(operatorID: "op", client: client)
        doc.invoiceNumber = "INV-0001"
        doc.discountAmount = 10
        doc.taxRate = 6
        context.insert(doc)
        var edits = DocumentEdits(discount: 10, taxRate: 6, dueDate: nil)
        edits.discountText = "1,2,3"
        edits.taxRateText = "105"
        #expect(edits.unreadableFields == ["Discount", "Tax"])
        #expect(edits.typedDiscount == nil && edits.typedTaxRate == nil)
        edits.apply(to: doc)
        #expect(doc.discountAmount == 10 && doc.taxRate == 6)
        edits.discountText = "15"
        edits.taxRateText = ""
        #expect(edits.unreadableFields.isEmpty)
        edits.apply(to: doc)
        #expect(doc.discountAmount == 15 && doc.taxRate == 0)
        _ = container
    }
}
