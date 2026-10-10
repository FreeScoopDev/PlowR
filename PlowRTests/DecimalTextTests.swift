//
//  DecimalTextTests.swift
//  PlowRTests
//

import Testing
import Foundation
@testable import PlowR

/// Numbers typed into text fields. The bug these pin: the decimal keypad
/// types a comma in many regions, and a price typed "12,50" was unreadable,
/// so it silently became the default price, or a 0 discount.
struct DecimalTextTests {

    @Test func oneCommaAndNoDotIsADecimalComma() {
        #expect(DecimalText.number("12,50") == 12.5)
        #expect(DecimalText.number(" 0,015 ") == 0.015)
        #expect(DecimalText.number(",5") == 0.5)
        #expect(DecimalText.number("12.50") == 12.5)
        #expect(DecimalText.number("12") == 12)
    }

    // Guessing which of a comma and a dot is the decimal could bill 1,000×.
    @Test func anythingElseWithACommaIsUnreadable() {
        for unreadable in ["1,250.00", "1.250,00", "1,2,3", "12,,5", ",", "", "  ", nil, "abc", "nan", "inf", "-inf"] {
            #expect(DecimalText.number(unreadable) == nil, "\(unreadable ?? "nil")")
        }
    }

    // Every money field reads through it: a line amount, a discount, a payment.
    @Test func aPriceTypedWithADecimalComma() {
        #expect(InvoiceLines.price(typed: "12,50", default: 0) == 12.5)
        #expect(InvoiceLines.price(typed: "12,3456", default: 0) == 12.35)     // to the cent
        #expect(InvoiceLines.price(typed: "1,250.00", default: 7) == 7)
        #expect(InvoiceLines.price(typed: "nan", default: 7) == 7)
    }

    @Test func theBuilderReadsADecimalComma() {
        let edging = DocumentDraft.Service(id: "edge", name: "Edging", unitType: "flat", pricePerUnit: 45)
        var d = DocumentDraft(services: [edging], zones: [], afterHoursMultiplier: 1)
        let key = DocumentDraft.key(serviceID: "edge", zoneIndex: -1)
        d.selections = [key]
        d.amounts[key] = "50,25"
        d.discount = "2,5"
        d.taxRate = "6,625"
        #expect(d.amount(forKey: key) == 50.25)
        #expect(d.discountAmount == 2.5)
        #expect(d.taxRatePercent == 6.625)
    }
}
