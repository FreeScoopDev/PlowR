//
//  DocumentTotalsTests.swift
//  PlowRTests
//

import Testing
import Foundation
import SwiftData
@testable import PlowR

/// One formula for a document's totals, and the tax rate kept as typed.
struct DocumentTotalsTests {

    // $100 of work, $10 off, 8.875 % tax: $90 taxed is $7.9875, billed as $7.99.
    @Test func discountComesOffThenTaxIsChargedToTheCent() {
        let t = Proposal.totals(subtotal: 100, discount: 10, taxRate: 8.875)
        #expect(t.discounted == 90)
        #expect(t.tax == 7.99)
        #expect(t.total == 97.99)
    }

    @Test func aDiscountLargerThanTheWorkLeavesNothingToPay() {
        let t = Proposal.totals(subtotal: 40, discount: 50, taxRate: 6)
        #expect(t.discounted == 0 && t.tax == 0 && t.total == 0)
    }

    @Test func aNegativeDiscountOrUnreadableTaxChangesNothing() {
        #expect(Proposal.totals(subtotal: 40, discount: -10, taxRate: 0).total == 40)
        #expect(Proposal.totals(subtotal: 40, discount: 0, taxRate: .nan).total == 40)
    }

    // Opening Edit and tapping Done saved 8.875 % as 8.9 %: the field showed one decimal.
    @Test func aTaxRateSurvivesTheEditScreenUnchanged() {
        for rate in [8.875, 8.9, 8.0, 0.5, 12.25, 7.125, 10.0] {
            #expect(Proposal.taxRate(typed: Proposal.percentText(rate)) == rate, "\(rate)")
        }
        #expect(Proposal.percentText(8.875) == "8.875")
        #expect(Proposal.percentText(8) == "8")
    }

    @Test func aTypedTaxRateIsANumberFromZeroToAHundred() {
        #expect(Proposal.taxRate(typed: " 6.35 ") == 6.35)
        for text in ["", "abc", "inf", "nan", "-5", "150"] {
            #expect(Proposal.taxRate(typed: text) == 0, "\(text)")
        }
    }
}

/// The same formula, on a saved document.
@MainActor
struct DocumentTotalsStoreTests {

    private func document(lines: [Double], discount: Double = 0, taxRate: Double = 0) throws -> (Proposal, ModelContainer) {
        let container = try ModelContainer(
            for: Proposal.self, ProposalLineItem.self, Client.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let client = Client(name: "Pat Doe", phone: "", address: "", operatorID: "op")
        context.insert(client)
        let proposal = Proposal(operatorID: "op", client: client)
        proposal.discountAmount = discount
        proposal.taxRate = taxRate
        let items = lines.enumerated().map { i, amount in
            ProposalLineItem(serviceName: "Line \(i)", zoneLabel: "", quantity: 1, unitType: "flat",
                             unitPrice: amount, sortOrder: i)
        }
        items.forEach { context.insert($0) }
        proposal.lineItems = items
        context.insert(proposal)
        return (proposal, container)
    }

    @Test func aSavedDocumentUsesTheSameFormula() throws {
        let (doc, container) = try document(lines: [60, 40], discount: 10, taxRate: 8.875)
        _ = container
        #expect(doc.total == Proposal.totals(subtotal: 100, discount: 10, taxRate: 8.875).total)
        #expect(doc.total == 97.99)
    }

    // The PDF printed the discount as entered, so its rows didn't add up.
    @Test func theDiscountShownIsTheDiscountTaken() throws {
        let (doc, container) = try document(lines: [30, 10], discount: 50)
        _ = container
        #expect(doc.appliedDiscount == 40)
        #expect(doc.subtotal - doc.appliedDiscount == doc.discountedTotal)
    }

    // A $149.50 invoice was texted to the client as $150.
    @Test func aReminderStatesTheAmountToTheCent() throws {
        let (doc, container) = try document(lines: [149.5])
        _ = container
        doc.invoiceNumber = "INV-0007"
        let text = doc.reminderMessage(locale: Locale(identifier: "en_US"))
        #expect(text.contains("$149.50"), "\(text)")
        #expect(text.contains("INV-0007"))
        #expect(text.hasPrefix("Hi Pat Doe,"))
    }
}
