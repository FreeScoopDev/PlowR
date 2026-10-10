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

    private func line(_ price: Double) -> ProposalLineItem {
        ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: price)
    }

    @Test func aNewDraftInvoiceCarriesTheBusinessesRate() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 6.625
        h.context.insert(profile)
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.taxRate == 6.625)
        #expect(invoice.total == 106.63)                                          // 6.625% of $100, to the cent
    }

    @Test func noRateSetMeansNoTax() throws {
        let h = try Harness(stopCount: 0)
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.taxRate == 0 && invoice.total == 100)
    }

    // Another business's rate on the same device isn't used.
    @Test func onlyThisBusinessesRateIsUsed() throws {
        let h = try Harness(stopCount: 0)
        let other = BusinessProfile(operatorID: "other")
        other.defaultTaxRate = 8
        h.context.insert(other)
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
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

    // A contract's payments are invoices like any other: the price is before tax.
    @Test func aContractPaymentCarriesTheBusinessesRate() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 5
        h.context.insert(profile)
        let contract = Contract(name: "Winter", startDate: h.clock, endDate: h.clock.addingTimeInterval(90 * 86400),
                                operatorID: "op")
        contract.pricingRaw = Contracts.Pricing.season.rawValue
        contract.price = 100
        contract.installments = 1
        contract.clientID = h.client.id.uuidString
        h.context.insert(contract)
        contract.client = h.client
        contract.signedAt = h.clock
        let payment = try #require(ContractInstallments.schedule(of: contract).first)
        let invoice = try #require(ContractInstallments.makeInvoice(for: payment, of: contract, in: h.context,
                                                                     now: h.clock))
        #expect(invoice.taxRate == 5 && invoice.total == 105)
    }

    // The builder's Tax field starts at the business's rate, or empty.
    @Test func theBuildersTaxFieldStartsAtTheBusinessesRate() {
        #expect(DocumentDraft.startingTaxText(rate: 6.625) == "6.625")
        #expect(DocumentDraft.startingTaxText(rate: 8) == "8")
        #expect(DocumentDraft.startingTaxText(rate: 0) == "")
        #expect(DocumentDraft.startingTaxText(rate: nil) == "")
    }

    // The keypad types a decimal comma in many regions; it was saved as 0%.
    @Test func aDecimalCommaIsARate() {
        #expect(Proposal.taxRate(typed: "6,625") == 6.625)
        #expect(Proposal.taxRate(typed: " 6.5 ") == 6.5)
        #expect(Proposal.taxRate(typed: "1,2,3") == 0)
        #expect(Proposal.taxRate(typed: "150") == 0)
        // Business Profile won't save what it can't read; empty is no tax.
        #expect(Proposal.readTaxRate("") == 0 && Proposal.readTaxRate("6,625") == 6.625)
        for unreadable in ["150", "6..5", "7.5.1", "abc", "-1"] {
            #expect(Proposal.readTaxRate(unreadable) == nil, "\(unreadable)")
        }
    }

    // MARK: Tax-exempt clients

    @Test func aTaxExemptClientsInvoiceStartsAtNoTax() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 6.625
        h.context.insert(profile)
        h.client.taxExempt = true
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.taxRate == 0 && invoice.total == 100)
        // A rate typed on the document still wins.
        invoice.taxRate = 5
        #expect(invoice.total == 105)
    }

    @Test func aTaxExemptClientsContractPaymentHasNoTax() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 5
        h.context.insert(profile)
        h.client.taxExempt = true
        let contract = Contract(name: "Winter", startDate: h.clock, endDate: h.clock.addingTimeInterval(90 * 86400),
                                operatorID: "op")
        contract.pricingRaw = Contracts.Pricing.season.rawValue
        contract.price = 100
        contract.installments = 1
        contract.clientID = h.client.id.uuidString
        h.context.insert(contract)
        contract.client = h.client
        contract.signedAt = h.clock
        let payment = try #require(ContractInstallments.schedule(of: contract).first)
        let invoice = try #require(ContractInstallments.makeInvoice(for: payment, of: contract, in: h.context,
                                                                     now: h.clock))
        #expect(invoice.taxRate == 0 && invoice.total == 100)
    }

    // Turning the switch on changes no document already made.
    @Test func theSwitchLeavesExistingDocumentsAlone() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 8
        h.context.insert(profile)
        let before = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                                now: h.clock, in: h.context)
        var draft = ClientDraft(h.client)
        draft.taxExempt = true
        draft.applyExceptAddressAndActive(to: h.client)
        #expect(h.client.taxExempt)
        #expect(before.taxRate == 8)
    }

    @Test func theBuilderStartsAnExemptClientAtNoTax() {
        #expect(DocumentDraft.startingTaxText(rate: 6.625, taxExempt: true) == "")
        #expect(DocumentDraft.startingTaxText(rate: 6.625, taxExempt: false) == "6.625")
        #expect(DocumentDraft.startingTaxRate(rate: 6.625, taxExempt: true) == 0)
        #expect(DocumentDraft.startingTaxRate(rate: nil, taxExempt: false) == 0)
    }

    // An edit synced from another device reaches an open client screen.
    @Test func theSwitchFollowsAChangeFromAnotherDevice() throws {
        let h = try Harness(stopCount: 0)
        let old = ClientDraft(h.client)
        var new = old
        new.taxExempt = true
        #expect(old.rebased(from: old, to: new).taxExempt)
    }
}

