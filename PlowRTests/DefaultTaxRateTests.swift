//
//  DefaultTaxRateTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The business's sales tax on every new invoice (pre-launch review,
/// 2026-10-10): invoices made from recorded work, billed work and contract
/// payments were always 0%.
@MainActor
struct DefaultTaxRateTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func line(_ h: Harness, _ price: Double) -> ProposalLineItem {
        ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: price)
    }

    @Test func aNewDraftInvoiceCarriesTheBusinessesRate() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 6.625
        h.context.insert(profile)
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(h, 100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.taxRate == 6.625)
        #expect(invoice.total == 106.63)                                          // 6.625% of $100, to the cent
    }

    @Test func noRateSetMeansNoTax() throws {
        let h = try Harness(stopCount: 0)
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(h, 100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.taxRate == 0 && invoice.total == 100)
    }

    // Another business's rate on the same device isn't used.
    @Test func onlyThisBusinessesRateIsUsed() throws {
        let h = try Harness(stopCount: 0)
        let other = BusinessProfile(operatorID: "other")
        other.defaultTaxRate = 8
        h.context.insert(other)
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(h, 100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.taxRate == 0)
    }

    @Test func aRevisionKeepsItsOriginalsRate() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 8
        h.context.insert(profile)
        let original = Proposal(operatorID: "op", client: h.client)
        original.invoiceNumber = "INV-0001"
        original.taxRate = 5
        h.context.insert(original)
        let revision = ServiceLog.revise(original, client: h.client, now: h.clock, in: h.context)
        #expect(revision.taxRate == 5)
    }
}
