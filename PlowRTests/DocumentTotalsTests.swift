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

    // A line typed as 10.125: printf prints 10.12, whole-cent rounding bills 10.13.
    // Rounding the sub-total once, first, keeps the printed rows adding up.
    @Test func aSubCentSubtotalIsRoundedOnceSoTheRowsAddUp() {
        let t = Proposal.totals(subtotal: 10.125, discount: 0, taxRate: 8)
        #expect(t.subtotal == 10.13)
        // Compared in whole cents: adding Doubles leaves floating-point dust.
        #expect(InvoiceLines.cents(t.subtotal) + InvoiceLines.cents(t.tax) == InvoiceLines.cents(t.total))
        #expect(String(format: "%.2f", t.subtotal) == "10.13")
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
        // Four decimals typed: kept to three, so the rate charged and printed agree.
        #expect(Proposal.taxRate(typed: "7.0625") == 7.063)
        #expect(Proposal.percentText(Proposal.taxRate(typed: "7.0625")) == "7.063")
        // A rate saved with four decimals before that prints as it's charged.
        #expect(Proposal.percentText(7.0625) == "7.0625")
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
        #expect(doc.total == 97.99)
        #expect(doc.taxAmount == 7.99)
    }

    // The PDF's rows, as printed, add up to its printed total, even for a line
    // typed with fractions of a cent.
    @Test func thePrintedRowsAddUpForASubCentLine() throws {
        let (doc, container) = try document(lines: [10.125], discount: 1, taxRate: 8)
        _ = container
        let printedLine = InvoiceLines.roundedToCent(doc.sortedLineItems[0].lineTotal)
        #expect(printedLine == doc.subtotal)
        let c = InvoiceLines.cents
        #expect(c(doc.subtotal) - c(doc.appliedDiscount) + c(doc.taxAmount) == c(doc.total))
        #expect(doc.total == 9.86)
    }

    // The PDF printed the discount as entered, so its rows didn't add up.
    @Test func theDiscountShownIsTheDiscountTaken() throws {
        let (doc, container) = try document(lines: [30, 10], discount: 50)
        _ = container
        #expect(doc.appliedDiscount == 40)
        #expect(doc.subtotal - doc.appliedDiscount == doc.discountedTotal)
    }

    // Two lines of 10.125 print as 10.13 each: the sub-total is their sum, 20.26,
    // not the rounded raw sum, 20.25.
    @Test func theSubtotalIsTheSumOfTheLinesAsPrinted() throws {
        let (doc, container) = try document(lines: [10.125, 10.125])
        _ = container
        #expect(doc.subtotal == 20.26)
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
