//
//  CSVExportTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Settings → Export Data: clients, invoices and the Service History as CSV.
@MainActor
struct CSVExportTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func rows(_ csv: String) -> [String] {
        #expect(csv.hasPrefix("\u{FEFF}"))
        return csv.dropFirst().components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    @Test func fieldsAreQuotedOnlyWhenTheyNeedIt() {
        #expect(CSVExport.escape("plain") == "plain")
        #expect(CSVExport.escape("1 Main St, Apt 2") == "\"1 Main St, Apt 2\"")
        #expect(CSVExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.escape("two\nlines") == "\"two\nlines\"")
    }

    // A note starting "=" mustn't run as a formula in a spreadsheet; money
    // (which can be negative) and dates are left as they are.
    @Test func textThatLooksLikeAFormulaIsDisarmed() {
        #expect(CSVExport.render(.text("=HYPERLINK(\"x\")")) == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(CSVExport.render(.text("+1 555")) == "'+1 555")
        #expect(CSVExport.render(.text("@home")) == "'@home")
        #expect(CSVExport.render(.plain("-5.00")) == "-5.00")
        #expect(CSVExport.render(.text("Gate code 4")) == "Gate code 4")
    }

    @Test func moneyAndDatesReadAsNumbersAndDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 23)))
        #expect(CSVExport.render(CSVExport.day(date, calendar: calendar)) == "2026-03-04")
        #expect(CSVExport.render(CSVExport.money(40.005)) == "40.01")
        #expect(CSVExport.render(CSVExport.money(1_204_560)) == "1204560.00")
    }

    @Test func clientsAreThisOperatorsByName() throws {
        let h = try Harness(stopCount: 2)
        h.clients[0].name = "Zed"
        h.clients[1].name = "Amy, Jr."
        h.clients[1].tags = ["commercial", "priority"]
        let other = Client(name: "Theirs", phone: "", address: "", operatorID: "someone else")
        let lines = rows(CSVExport.clients(h.clients + [other], operatorID: "op"))
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Name,Phone,Email,Address,Status"))
        #expect(lines[1].hasPrefix("\"Amy, Jr.\","))
        #expect(lines[1].contains("commercial; priority"))
        #expect(lines[2].hasPrefix("Zed,"))
    }

    @Test func invoicesOnlyWithTheirTotals() throws {
        let h = try Harness(stopCount: 1)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0007"
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 40)
        h.context.insert(item)
        invoice.lineItems = [item]
        let quote = Proposal(operatorID: "op", client: h.client)
        [invoice, quote].forEach { h.context.insert($0) }
        let lines = rows(CSVExport.invoices([invoice, quote], operatorID: "op"))
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("INV-0007,"))
        #expect(lines[1].contains(",40.00,0.00,0.00,40.00,"))
    }

    @Test func theServiceHistoryHasEachJobWithItsBilling() throws {
        let h = try Harness(stopCount: 1)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0003"
        h.context.insert(invoice)
        let billed = ServiceRecord(operatorID: "op", sourceKey: "a", source: .route)
        billed.clientName = "Pat"
        billed.lines = [.init(serviceID: "c", name: "Clear", unitType: "flat", price: 40),
                        .init(serviceID: "s", name: "Salt", unitType: "flat", price: 10)]
        billed.invoiceID = invoice.id.uuidString
        billed.minutes = 12.4
        billed.performedAt = h.clock
        let earlier = ServiceRecord(operatorID: "op", sourceKey: "b", source: .beforeLog)
        earlier.clientName = "Pat"
        earlier.performedAt = h.clock.addingTimeInterval(-86_400)
        [billed, earlier].forEach { h.context.insert($0) }
        let lines = rows(CSVExport.serviceHistory([billed, earlier], operatorID: "op", in: h.context))
        #expect(lines.count == 3)
        #expect(lines[1].contains("Before the Service History"))
        #expect(lines[1].contains("Billing Not Tracked"))
        #expect(lines[2].contains("Clear; Salt,12,50.00,50.00,Invoiced,INV-0003"))    // Total, then Charged
    }

    @Test func aFileIsNamedForItsKindAndDay() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "CSVExportTests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try CSVExport.file("Clients", contents: "a,b\r\n", directory: dir)
        #expect(url.lastPathComponent.hasPrefix("PlowR Clients "))
        #expect(url.pathExtension == "csv")
        #expect(try String(contentsOf: url, encoding: .utf8) == "a,b\r\n")
    }

    // Quotes not yet invoices: the Invoices file leaves them out.
    @Test func proposalsAreTheQuotesNotTheInvoices() throws {
        let h = try Harness(stopCount: 1)
        let quote = Proposal(operatorID: "op", client: h.client)
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 40)
        h.context.insert(item)
        quote.lineItems = [item]
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0007"
        let theirs = Proposal(operatorID: "someone else", client: h.client)
        [quote, invoice, theirs].forEach { h.context.insert($0) }
        let lines = rows(CSVExport.proposals([quote, invoice, theirs], operatorID: "op"))
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Created,Client,Address,Services"))
        #expect(lines[1].contains("Clear") && lines[1].contains("40.00"))
    }

    @Test func theScheduleIsEveryVisitByDate() throws {
        let h = try Harness(stopCount: 1)
        let service = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 40, operatorID: "op")
        h.context.insert(service)
        let later = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: "Later",
                                   clientAddress: "2 Elm St", scheduledDate: Date(timeIntervalSince1970: 1_900_000_000))
        later.expectedServiceIDs = [service.id.uuidString]
        let sooner = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: "Sooner",
                                    clientAddress: "1 Main St", scheduledDate: Date(timeIntervalSince1970: 1_800_000_000))
        sooner.status = .completed
        [later, sooner].forEach { h.context.insert($0) }
        let lines = rows(CSVExport.schedule([later, sooner], operatorID: "op", catalog: [service]))
        #expect(lines.count == 3)
        #expect(lines[1].contains("Sooner") && lines[1].contains("Completed"))
        #expect(lines[2].contains("Later") && lines[2].contains("Mowing"))
    }
}
