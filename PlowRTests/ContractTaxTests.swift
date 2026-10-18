//
//  ContractTaxTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
import PDFKit
@testable import PlowR

/// A contract's prices are before tax, and say so (money review, decision
/// 3, 2026-10-18): a client signed "$900 season, 3 payments" and was billed
/// three $324 invoices at 8% without a word about tax on the contract or the
/// Dashboard. A contract made from a proposal keeps the proposal's rate.
@MainActor
struct ContractTaxTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func business(_ h: Harness, rate: Double) {
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = rate
        h.context.insert(profile)
    }

    private func signed(_ h: Harness, price: String, pricing: Contracts.Pricing = .season, installments: Int = 1,
                        taxRate: Double? = nil) -> Contract {
        var draft = Contracts.Draft(for: h.client, now: h.clock)
        draft.priceText = price
        draft.pricing = pricing
        draft.installments = installments
        draft.taxRate = taxRate
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        Contracts.sign(contract, in: h.context, now: h.clock)
        return contract
    }

    private func priceLines(_ contract: Contract, _ h: Harness, defaultTaxRate: Double?) -> [String] {
        let sections = ContractPDF.sections(of: contract, client: h.client, catalog: [], defaultTaxRate: defaultTaxRate)
        return sections.first { $0.heading == "Price" }?.lines ?? []
    }

    private func invoices(_ contract: Contract, _ h: Harness) -> [Proposal] {
        ContractInstallments.schedule(of: contract).compactMap {
            ContractInstallments.makeInvoice(for: $0, of: contract, in: h.context, now: h.clock)
        }
    }

    private func allDue(_ contract: Contract) -> [(contract: Contract, installment: ContractInstallments.Installment)] {
        ContractInstallments.schedule(of: contract).map { (contract, $0) }
    }

    // The example: $900 in 3 payments at 8% is three $324 invoices.
    @Test func thePDFAndDashboardShowWhatEachInvoiceBills() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 8)
        let contract = signed(h, price: "900", installments: 3)
        let lines = priceLines(contract, h, defaultTaxRate: 8)
        #expect(lines.first == "$900.00 season, 3 payments, plus tax")
        #expect(lines.count == 5)                                                 // summary, 3 payments, extras note
        for line in lines[1...3] { #expect(line.hasSuffix(": $300.00 + 8% tax = $324.00"), "\(line)") }
        #expect(ContractInstallments.amountDue(allDue(contract), defaultTaxRate: 8) == 972)
        #expect(invoices(contract, h).map(\.total) == [324, 324, 324])
    }

    // Payments that don't split evenly, at a rate that rounds: every line and
    // the Dashboard come to exactly what the invoices bill.
    @Test func everyAmountMatchesItsInvoiceToTheCent() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 8.875)
        let contract = signed(h, price: "100", installments: 3)
        let lines = priceLines(contract, h, defaultTaxRate: 8.875)
        let made = invoices(contract, h)
        #expect(made.count == 3 && made.allSatisfy { $0.taxRate == 8.875 })
        for (line, invoice) in zip(lines[1...3], made) {
            #expect(line.hasSuffix("% tax = \(invoice.total.formatted(.currency(code: "USD")))"), "\(line)")
        }
        #expect(made.map(\.total) == [36.29, 36.29, 36.30])
        #expect(ContractInstallments.amountDue(allDue(contract), defaultTaxRate: 8.875)
                == InvoiceLines.roundedToCent(made.reduce(0) { $0 + $1.total }))
    }

    @Test func aSinglePaymentAndAVisitPriceSayTheirTaxedAmount() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 8)
        let season = signed(h, price: "900")
        #expect(priceLines(season, h, defaultTaxRate: 8).prefix(2)
                == ["$900.00 season, plus tax", "$900.00 + 8% tax = $972.00"])
        // A visit's charge goes on the visit's invoice, at the business's rate.
        let perVisit = signed(h, price: "50", pricing: .perVisit, taxRate: 6)
        #expect(priceLines(perVisit, h, defaultTaxRate: 8)
                == ["$50.00 per visit, plus tax", "$50.00 + 8% tax = $54.00 a visit"])
    }

    @Test func aMonthlyPriceSaysPlusTaxOnEachMonth() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 8)
        let monthly = signed(h, price: "120", pricing: .monthly)
        let lines = priceLines(monthly, h, defaultTaxRate: 8)
        #expect(lines.first == "$120.00 a month, plus tax")
        let months = lines.dropFirst().dropLast()                                 // the extras note last
        #expect(!months.isEmpty && months.allSatisfy { $0.hasSuffix(": $120.00 + 8% tax = $129.60") })
    }

    // No rate, or a tax-exempt client: the page is as it was, and nothing is taxed.
    @Test func noTaxSaysNothingAboutTax() throws {
        let h = try Harness(stopCount: 0)
        let untaxed = signed(h, price: "900", installments: 3)
        let lines = priceLines(untaxed, h, defaultTaxRate: nil)
        #expect(lines.first == "$900.00 season, 3 payments")
        #expect(lines[1...3].allSatisfy { $0.hasSuffix(": $300.00") })
        #expect(ContractInstallments.amountDue(allDue(untaxed), defaultTaxRate: 0) == 900)

        business(h, rate: 8)
        h.client.taxExempt = true
        let exempt = signed(h, price: "900", installments: 3, taxRate: 6)
        #expect(!priceLines(exempt, h, defaultTaxRate: 8).joined().contains("tax"))
        #expect(ContractInstallments.amountDue(allDue(exempt), defaultTaxRate: 8) == 900)
        #expect(invoices(exempt, h).map(\.total) == [300, 300, 300])
    }

    // The client was quoted 6%; the business's rate is 8%.
    @Test func aContractFromAProposalKeepsItsRate() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 8)
        let proposal = Proposal(operatorID: "op", client: h.client)
        let item = ProposalLineItem(serviceName: "Plowing", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 900)
        h.context.insert(item)
        h.context.insert(proposal)
        proposal.lineItems = [item]
        proposal.taxRate = 6
        let draft = Contracts.draft(from: proposal, client: h.client, catalog: [], now: h.clock)
        #expect(draft.taxRate == 6 && draft.price == 900)
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        Contracts.sign(contract, in: h.context, now: h.clock)
        #expect(contract.taxRate == 6)
        #expect(priceLines(contract, h, defaultTaxRate: 8).contains("$900.00 + 6% tax = $954.00"))
        #expect(ContractInstallments.amountDue(allDue(contract), defaultTaxRate: 8) == 954)
        let invoice = try #require(invoices(contract, h).first)
        #expect(invoice.taxRate == 6 && invoice.total == 954)
        // Editing and renewing keep it.
        var edit = Contracts.Draft(contract)
        #expect(edit.taxRate == 6)
        edit.notes = "Edited"
        Contracts.save(edit, to: contract, of: h.client, in: h.context)
        #expect(contract.taxRate == 6)
        #expect(Contracts.renewal(of: contract, now: h.clock).taxRate == 6)
    }

    // A proposal quoted without tax makes a contract billed without tax.
    @Test func aProposalAtNoTaxMakesAnUntaxedContract() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 8)
        let proposal = Proposal(operatorID: "op", client: h.client)
        h.context.insert(proposal)
        var draft = Contracts.draft(from: proposal, client: h.client, catalog: [], now: h.clock)
        draft.priceText = "900"
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        Contracts.sign(contract, in: h.context, now: h.clock)
        #expect(contract.taxRate == 0)
        #expect(!priceLines(contract, h, defaultTaxRate: 8).joined().contains("tax"))
        #expect(invoices(contract, h).first?.total == 900)
    }

    // The contract page's Payments footer says the rate each invoice adds, or nothing.
    @Test func thePaymentsFooterSaysTheTax() throws {
        let h = try Harness(stopCount: 0)
        let contract = signed(h, price: "900", installments: 3, taxRate: 6)
        let plain = "On a payment's date, Make Invoice makes its draft, ready for you to send. Nothing is sent by itself."
        #expect(Contracts.paymentsNote(of: contract, defaultRate: 8)
                == plain + " Amounts not invoiced yet are before tax: each invoice adds 6% tax.")
        let untaxed = signed(h, price: "900", installments: 3)
        #expect(Contracts.paymentsNote(of: untaxed, defaultRate: 0) == plain)
        h.client.taxExempt = true
        #expect(Contracts.paymentsNote(of: contract, defaultRate: 8) == plain)
    }

    // What the client is sent: the page itself, not only its text model.
    @Test func theRenderedPDFSaysPlusTax() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 8
        h.context.insert(profile)
        let contract = signed(h, price: "900")
        let data = ContractPDF.generate(contract, client: h.client, profile: profile, catalog: [], madeWithPlowR: true)
        let document = try #require(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        #expect(text.contains("plus tax") && text.contains("$972.00"), "\(text)")
    }

    // A proposal's contract switched to monthly keeps the quoted rate.
    @Test func aMonthlyContractKeepsItsOwnRate() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 8)
        let monthly = signed(h, price: "100", pricing: .monthly, taxRate: 6)
        #expect(Contracts.taxRate(of: monthly, defaultRate: 8) == 6)
        #expect(priceLines(monthly, h, defaultTaxRate: 8).dropFirst().first?.hasSuffix(": $100.00 + 6% tax = $106.00") == true)
        #expect(invoices(monthly, h).first?.total == 106)
    }

    // The rate is set when the contract is made; saving an edit never rewrites it.
    @Test func editingNeverRewritesTheRate() throws {
        let h = try Harness(stopCount: 0)
        let contract = signed(h, price: "900", taxRate: 6)
        var edit = Contracts.Draft(contract)
        edit.taxRate = nil
        Contracts.save(edit, to: contract, of: h.client, in: h.context)
        #expect(contract.taxRate == 6)
    }

    // Every other contract (and every one made before) follows the business's rate.
    @Test func otherContractsUseTheBusinessesRate() throws {
        let h = try Harness(stopCount: 0)
        business(h, rate: 5)
        let contract = signed(h, price: "100")
        #expect(contract.taxRate == nil)
        #expect(Contracts.taxRate(of: contract, defaultRate: 5) == 5)
        #expect(invoices(contract, h).first?.total == 105)
    }
}
