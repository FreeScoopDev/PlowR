//
//  ContractRenewalTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
import PDFKit
@testable import PlowR

/// A contract from a proposal, renewing one, its PDF and its export.
@MainActor
struct ContractRenewalTests {
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func catalog(_ h: Harness) -> [ServiceItem] {
        let plow = ServiceItem(name: "Plowing", category: "snow", unitType: "flat", pricePerUnit: 60, operatorID: "op")
        let walks = ServiceItem(name: "Walkways", category: "snow", unitType: "flat", pricePerUnit: 20, operatorID: "op")
        let theirs = ServiceItem(name: "Plowing", category: "snow", unitType: "flat", pricePerUnit: 60, operatorID: "other")
        [plow, walks, theirs].forEach { h.context.insert($0) }
        return [plow, walks, theirs]
    }

    private func signed(_ h: Harness, _ draft: Contracts.Draft) -> Contract {
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        Contracts.sign(contract, in: h.context, now: h.clock)
        return contract
    }

    @Test func aProposalBecomesADraftContract() throws {
        let h = try Harness(stopCount: 0)
        let services = catalog(h)
        let proposal = Proposal(operatorID: "op", client: h.client)
        proposal.notes = "Plowed at 2 in"
        let items = [("plowing", 600.0), ("Haul away", 300.0)].map { name, price -> ProposalLineItem in
            let item = ProposalLineItem(serviceName: name, zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: price)
            h.context.insert(item)
            return item
        }
        h.context.insert(proposal)
        proposal.lineItems = items
        let draft = Contracts.draft(from: proposal, client: h.client, catalog: services, now: h.clock)
        #expect(draft.serviceIDs == [services[0].id.uuidString])                  // by name, this business's
        #expect(draft.pricing == .season && draft.price == 900)
        proposal.taxRate = 8                                                      // before tax: payments carry none
        #expect(Contracts.draft(from: proposal, client: h.client, catalog: services, now: h.clock).price == 900)
        h.client.expectedServiceIDs = ["usual"]
        let unmatched = Proposal(operatorID: "op", client: h.client)
        h.context.insert(unmatched)
        #expect(Contracts.draft(from: unmatched, client: h.client, catalog: services, now: h.clock).serviceIDs.isEmpty)
        #expect(draft.notes == "Plowed at 2 in")
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        #expect(contract.sourceProposalID == proposal.id.uuidString)
        #expect(contract.signedAt == nil)                                         // checked and signed by hand
        #expect(Contracts.madeFrom(proposal, among: [contract])?.id == contract.id)
        #expect(Contracts.madeFrom(unmatched, among: [contract]) == nil)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? .distantPast
    }

    private func season(_ h: Harness, from start: Date, to end: Date) -> Contract {
        let contract = Contract(name: "", startDate: start, endDate: end, operatorID: "op")
        contract.name = Contracts.name(from: start, to: end)
        contract.price = 900
        contract.installments = 3
        contract.serviceIDs = ["plow"]
        contract.placeIDs = [h.client.id.uuidString]
        contract.clientID = h.client.id.uuidString
        contract.scheduleWeekdays = [3]
        h.context.insert(contract)
        contract.client = h.client
        contract.signedAt = start
        return contract
    }

    // Winter renews into next winter; a year's into the next year, leap year or not.
    @Test func aRenewalIsTheSameMonthsNextSeason() throws {
        let h = try Harness(stopCount: 0)
        let winter = season(h, from: date(2026, 11, 1), to: date(2027, 3, 31))
        let next = Contracts.renewal(of: winter, now: date(2027, 3, 20), calendar: calendar)
        #expect(next.startDate == date(2027, 11, 1) && next.endDate == date(2028, 3, 31))
        let year = season(h, from: date(2027, 1, 1), to: date(2027, 12, 31))
        let nextYear = Contracts.renewal(of: year, now: date(2027, 12, 1), calendar: calendar)
        #expect(nextYear.startDate == date(2028, 1, 1) && nextYear.endDate == date(2028, 12, 31))
        // Renewed long after it ended: the next season that hasn't passed.
        let late = Contracts.renewal(of: winter, now: date(2029, 1, 10), calendar: calendar)
        #expect(late.startDate == date(2028, 11, 1) && late.endDate == date(2029, 3, 31))
    }

    @Test func aRenewalKeepsTheTermsAtTheRaisedPrice() throws {
        let h = try Harness(stopCount: 0)
        let winter = season(h, from: date(2026, 11, 1), to: date(2027, 3, 31))
        let renewal = Contracts.renewal(of: winter, increasePercent: 5, now: date(2027, 3, 20), calendar: calendar)
        #expect(renewal.price == 945 && renewal.installments == 3 && !renewal.isSigned)
        #expect(renewal.serviceIDs == ["plow"] && renewal.scheduleWeekdays == [3])
        #expect(renewal.name.isEmpty)                                             // named from its new dates
        #expect(Contracts.renewal(of: winter, increasePercent: 3.3, now: date(2027, 3, 20), calendar: calendar).price == 929.7)
        #expect(Contracts.canRenew(winter, among: [winter]))
        let next = Contracts.save(renewal, to: nil, of: h.client, in: h.context)
        #expect(next.renewedFromID == winter.id.uuidString)
        #expect(!Contracts.canRenew(winter, among: [winter, next]))               // renewed once
        #expect(!Contracts.canRenew(next, among: [winter, next]))                 // a draft isn't
        // Edited later: still the renewal.
        var edit = Contracts.Draft(next)
        edit.name = "Winter"
        Contracts.save(edit, to: next, of: h.client, in: h.context)
        #expect(next.renewedFromID == winter.id.uuidString)
    }

    @Test func aCancelledContractIsntRenewed() throws {
        let h = try Harness(stopCount: 0)
        let winter = season(h, from: date(2026, 11, 1), to: date(2027, 3, 31))
        winter.cancelledAt = date(2027, 1, 5)
        #expect(!Contracts.canRenew(winter, among: [winter]))
    }

    // Long terms run on to more pages; nothing is cut off.
    @Test func longTermsRunOnToMorePages() throws {
        let h = try Harness(stopCount: 0)
        let winter = season(h, from: date(2026, 11, 1), to: date(2027, 3, 31))
        winter.notes = (1...200).map { "Clause \($0): the client agrees to keep the driveway clear of vehicles." }
            .joined(separator: "\n") + "\nTHE LAST LINE."
        let document = try #require(PDFDocument(data: ContractPDF.generate(winter, client: h.client, profile: nil, catalog: [], madeWithPlowR: true)))
        #expect(document.pageCount >= 3)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        #expect(text.contains("THE LAST LINE."))
        #expect(text.contains("Agreed by"))
    }

    // PlowR's line on a free-tier contract, never on a Pro one.
    @Test func aContractCarriesPlowRsLineOnlyWhenAsked() throws {
        let h = try Harness(stopCount: 0)
        let winter = season(h, from: date(2026, 11, 1), to: date(2027, 3, 31))
        func text(_ madeWithPlowR: Bool) throws -> String {
            let document = try #require(PDFDocument(data: ContractPDF.generate(winter, client: h.client, profile: nil,
                                                                               catalog: [], madeWithPlowR: madeWithPlowR)))
            return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        }
        #expect(try text(true).contains("Prepared with PlowR"))
        #expect(try !text(false).contains("Prepared with PlowR"))
    }

    // One paragraph longer than a page breaks between words, and carries on.
    @Test func aParagraphLongerThanAPageCarriesOn() throws {
        let h = try Harness(stopCount: 0)
        let winter = season(h, from: date(2026, 11, 1), to: date(2027, 3, 31))
        winter.notes = Array(repeating: "The client agrees to keep the driveway clear.", count: 150).joined(separator: " ")
            + " FINALWORD"
        let document = try #require(PDFDocument(data: ContractPDF.generate(winter, client: h.client, profile: nil, catalog: [], madeWithPlowR: true)))
        #expect(document.pageCount >= 2)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: " ")
        #expect(text.contains("FINALWORD"))
    }

    @Test func theFileNamesTheClient() throws {
        let h = try Harness(stopCount: 0)
        let winter = season(h, from: date(2026, 11, 1), to: date(2027, 3, 31))
        winter.clientName = "Pat: Smith/Jones"
        #expect(ContractPDF.fileName(winter).hasPrefix("Contract - Pat- Smith-Jones - "))
        winter.name = String(repeating: "x", count: 300)
        #expect(ContractPDF.fileName(winter).count <= 96)
    }

    @Test func thePDFSaysWhatWasAgreed() throws {
        let h = try Harness(stopCount: 0)
        let services = catalog(h)
        var draft = Contracts.Draft(for: h.client, now: h.clock)
        draft.serviceIDs = [services[0].id.uuidString]
        draft.priceText = "900"
        draft.installments = 3
        draft.triggerInches = 2
        draft.notes = "Driveway and front walk."
        let season = signed(h, draft)
        let sections = ContractPDF.sections(of: season, client: h.client, catalog: services)
        let byHeading = Dictionary(uniqueKeysWithValues: sections.map { ($0.heading, $0.lines) })
        #expect(byHeading["Client"]?.first == h.client.name)
        #expect(byHeading["Services Covered"] == ["Plowing"])
        #expect(byHeading["Price"]?.first == "$900.00 season, 3 payments")
        #expect(byHeading["Price"]?.count == 5)                                   // summary, 3 payments, extras note
        #expect(byHeading["Trigger"]?.first?.contains("2 in") == true)
        #expect(byHeading["Terms"] == ["Driveway and front walk."])
        #expect(byHeading["Visits"] == nil)
        #expect(!ContractPDF.generate(season, client: h.client, profile: nil, catalog: services, madeWithPlowR: true).isEmpty)
    }

    @Test func contractsAreExported() throws {
        let h = try Harness(stopCount: 0)
        let services = catalog(h)
        var draft = Contracts.Draft(for: h.client, now: h.clock)
        draft.serviceIDs = [services[0].id.uuidString]
        draft.priceText = "900"
        draft.name = "Winter"
        _ = signed(h, draft)
        let csv = CSVExport.contracts(Contracts.all(in: h.context), operatorID: "op", catalog: services, now: h.clock)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("Contract,Client,Status,Starts,Ends,Pricing,Price,Payments,Services,Visits,Signed,Cancelled,Notes"))
        #expect(lines[1].hasPrefix("Winter,\(h.client.name),Active,"))
        #expect(lines[1].contains("Season Price,900.00,1,Plowing"))
    }
}
