//
//  ProDocumentsTests.swift
//  PlowRTests
//

import Foundation
import PDFKit
import Testing
@testable import PlowR

/// PlowR Pro and documents: PlowR's line on free-tier documents only, and,
/// read only, sharing only an invoice with money still owed.
@MainActor
struct ProDocumentsTests {
    // MARK: The footer

    @Test func theFooterCarriesPlowRsLineUnlessPro() {
        #expect(PDFGenerator.footerText(companyName: "Acme Grounds", madeWithPlowR: true)
                == "Acme Grounds  ·  Prepared with PlowR · getplowr.app")
        #expect(PDFGenerator.footerText(companyName: "Acme Grounds", madeWithPlowR: false) == "Acme Grounds")
        #expect(PDFGenerator.footerText(companyName: "  ", madeWithPlowR: true) == PDFGenerator.plowRLine)
        #expect(PDFGenerator.footerText(companyName: nil, madeWithPlowR: false).isEmpty)
    }

    @Test func freeAndCancelledShowTheLineProDoesnt() {
        #expect(Access(plan: .free, clientCount: 3).showsMadeWithPlowR)
        #expect(Access(plan: .lapsed, clientCount: 3).showsMadeWithPlowR)
        #expect(Access(plan: .lapsed, clientCount: 11).showsMadeWithPlowR)
        #expect(!Access(plan: .pro, clientCount: 3).showsMadeWithPlowR)
    }

    private func text(of data: Data) throws -> String {
        let document = try #require(PDFDocument(data: data))
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    @Test func anInvoicePrintsTheLineOnlyWhenAsked() throws {
        let client = Client(name: "Pat", phone: "", address: "", operatorID: "op")
        let invoice = Proposal(operatorID: "op", client: client)
        let free = try text(of: PDFGenerator.generate(proposal: invoice, profile: nil, forceIsInvoice: true,
                                                      madeWithPlowR: true))
        let pro = try text(of: PDFGenerator.generate(proposal: invoice, profile: nil, forceIsInvoice: true,
                                                     madeWithPlowR: false))
        #expect(free.contains("Prepared with PlowR"))
        #expect(!pro.contains("PlowR"))
    }

    @Test func theSeasonReportPrintsTheLineOnlyWhenAsked() throws {
        let free = try text(of: PDFGenerator.generateSeasonReport(clients: [], proposals: [], profile: nil,
                                                                  madeWithPlowR: true))
        let pro = try text(of: PDFGenerator.generateSeasonReport(clients: [], proposals: [], profile: nil,
                                                                 madeWithPlowR: false))
        #expect(free.contains("Prepared with PlowR"))
        #expect(!pro.contains("Prepared with PlowR"))
    }

    // MARK: Sharing, read only

    @Test func readOnlySharesOnlyAnInvoiceStillOwed() {
        let readOnly = Access(plan: .lapsed, clientCount: 40)
        #expect(readOnly.canShareDocument(isInvoice: true, owed: 120))
        #expect(!readOnly.canShareDocument(isInvoice: true, owed: 0))
        #expect(!readOnly.canShareDocument(isInvoice: false, owed: 120))
        #expect(ProGate.shareDocument(readOnly, isInvoice: true, owed: 0) == .readOnly)
        #expect(ProGate.shareDocument(readOnly, isInvoice: true, owed: 120) == nil)
        #expect(ProGate.makeReport(readOnly) == .readOnly)
        #expect(ProGate.makeDocument(readOnly) == .readOnly)
        // A cent owed is owed; less than Payments' tolerance isn't.
        #expect(readOnly.canShareDocument(isInvoice: true, owed: 0.01))
        #expect(!readOnly.canShareDocument(isInvoice: true, owed: 0.004))
    }

    @Test func everyoneElseSharesAnything() {
        for access in [Access(plan: .pro, clientCount: 40), Access(plan: .free, clientCount: 3),
                       Access(plan: .lapsed, clientCount: 10)] {
            #expect(access.canShareDocument(isInvoice: false, owed: 0))
            #expect(ProGate.makeReport(access) == nil)
            #expect(ProGate.makeDocument(access) == nil)
        }
    }
}
