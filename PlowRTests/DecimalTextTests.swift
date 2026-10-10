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

    private let german = Locale(identifier: "de_DE")
    private let us = Locale(identifier: "en_US")

    @Test func oneCommaAndNoDotIsADecimalCommaWhereTheRegionWritesOne() {
        #expect(DecimalText.number("12,50", locale: german) == 12.5)
        #expect(DecimalText.number(" 0,015 ", locale: german) == 0.015)
        #expect(DecimalText.number(",5", locale: german) == 0.5)
        #expect(DecimalText.number("12.50", locale: german) == 12.5)
        #expect(DecimalText.number("12", locale: german) == 12)
    }

    // Read as a decimal, an iPad's "1,250" in the US would record $1.25.
    @Test func aCommaIsNotADecimalWhereTheRegionWritesADot() {
        #expect(DecimalText.number("1,250", locale: us) == nil)
        #expect(DecimalText.number("12,50", locale: us) == nil)
        #expect(DecimalText.number(" 12.50 ", locale: us) == 12.5)
    }

    // Guessing which of a comma and a dot is the decimal could bill 1,000×.
    @Test func anythingElseWithACommaIsUnreadable() {
        for unreadable in ["1,250.00", "1.250,00", "1,2,3", "12,,5", ",", "", "  ", nil, "abc", "nan", "inf", "-inf"] {
            #expect(DecimalText.number(unreadable, locale: german) == nil, "\(unreadable ?? "nil")")
        }
    }

    // Every money field reads through it: a line amount, a discount, a payment.
    @Test func aPriceTypedWithADecimalComma() {
        #expect(InvoiceLines.price(typed: "12,50", default: 0, locale: german) == 12.5)
        #expect(InvoiceLines.price(typed: "12,3456", default: 0, locale: german) == 12.35)   // to the cent
        #expect(InvoiceLines.price(typed: "1,250.00", default: 7, locale: german) == 7)
        #expect(InvoiceLines.price(typed: "nan", default: 7, locale: german) == 7)
        #expect(InvoiceLines.price(typed: "1,250", default: 0, locale: us) == 0)
    }

    @Test func theBuilderReadsADecimalComma() {
        let edging = DocumentDraft.Service(id: "edge", name: "Edging", unitType: "flat", pricePerUnit: 45)
        var d = DocumentDraft(services: [edging], zones: [], afterHoursMultiplier: 1)
        d.locale = german
        let key = DocumentDraft.key(serviceID: "edge", zoneIndex: -1)
        d.selections = [key]
        d.amounts[key] = "50,25"
        d.discount = "2,5"
        d.taxRate = "6,625"
        #expect(d.amount(forKey: key) == 50.25)
        #expect(d.discountAmount == 2.5)
        #expect(d.taxRatePercent == 6.625)
    }

    // Unreadable used to save $0 over the service's price; Save now waits.
    @Test func aCatalogPriceIsReadOrNotSaved() {
        #expect(ServiceCatalog.price(typed: "0,015", locale: german) == 0.015)    // a rate, not rounded
        #expect(ServiceCatalog.price(typed: "45", locale: german) == 45)
        #expect(ServiceCatalog.price(typed: "0", locale: german) == 0)
        for unreadable in ["", "1.250,00", "1,250.00", "abc", "-5", "1e12", "nan"] {
            #expect(ServiceCatalog.price(typed: unreadable, locale: german) == nil, "\(unreadable)")
        }
        #expect(ServiceCatalog.price(typed: "1,250", locale: us) == nil)
    }
}
