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
        h.clients[1].taxExempt = true
        let other = Client(name: "Theirs", phone: "", address: "", operatorID: "someone else")
        let lines = rows(CSVExport.clients(h.clients + [other], operatorID: "op"))
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Name,Phone,Email,Address,Status"))
        #expect(lines[1].hasPrefix("\"Amy, Jr.\","))
        #expect(lines[1].contains("commercial; priority"))
        // Tax Exempt beside the other billing preferences: Yes for Amy, No for Zed.
        #expect(lines[0].contains(",No Charge,Tax Exempt,Discount %,"))
        #expect(lines[1].contains(",No,Yes,0,") && lines[2].contains(",No,No,0,"))
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
        // Subtotal, Discount, Tax Rate %, Tax, Total.
        #expect(lines[0].contains(",Subtotal,Discount,Tax Rate %,Tax,Total,"))
        #expect(lines[1].contains(",40.00,0.00,0,0.00,40.00,"))
    }

    @Test func invoicesSayTheTaxRateCharged() throws {
        let h = try Harness(stopCount: 1)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0008"
        invoice.taxRate = 8.875
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 100)
        h.context.insert(item)
        invoice.lineItems = [item]
        h.context.insert(invoice)
        let lines = rows(CSVExport.invoices([invoice], operatorID: "op"))
        #expect(lines[1].contains(",100.00,0.00,8.875,8.88,108.88,"))
    }

    /// One row per line of each invoice billed, so income can be split by
    /// service: not a proposal, a draft, a revised invoice (its revision has
    /// its lines), or another business's; a void invoice that kept its
    /// money is.
    @Test func invoiceLinesListEveryServiceBilled() throws {
        let h = try Harness(stopCount: 1)
        func document(_ number: String, operatorID: String = "op", lines: [ProposalLineItem]) -> Proposal {
            let doc = Proposal(operatorID: operatorID, client: h.client)
            doc.invoiceNumber = number
            lines.forEach { h.context.insert($0) }
            doc.lineItems = lines
            h.context.insert(doc)
            return doc
        }
        func flat(_ name: String, _ price: Double, order: Int = 0) -> ProposalLineItem {
            ProposalLineItem(serviceName: name, zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: price, sortOrder: order)
        }
        let clear = ProposalLineItem(serviceName: "Clear", zoneLabel: "Driveway", quantity: 1_000,
                                     unitType: "perSqFt", unitPrice: 0.035, sortOrder: 0)
        let salt = flat("Salt", 50, order: 1)
        salt.lineTotal = 75                       // amount edited; unitPrice still says 50
        let sent = document("INV-0009", lines: [salt, clear])
        sent.invoiceSentAt = h.clock
        let original = document("INV-0004", lines: [flat("Mow", 300)])
        original.invoiceSentAt = h.clock
        original.voidedAt = h.clock               // revised: the revision has its lines
        let revision = document("INV-0005", lines: [flat("Mow", 300)])
        revision.revisionOf = "INV-0004"
        _ = document("INV-0006", lines: [flat("Rake", 40)])                       // draft, never sent
        let paidThenVoided = document("INV-0007", lines: [flat("Edge", 60)])      // Void keeps its money
        paidThenVoided.invoiceSentAt = h.clock
        let kept = Payment(amount: 60, method: "Cash", receivedAt: h.clock, operatorID: "op")
        h.context.insert(kept)
        paidThenVoided.payments = [kept]
        paidThenVoided.voidedAt = h.clock
        let quote = document("", lines: [flat("Quote", 99)])                      // a proposal
        let theirs = document("INV-0001", operatorID: "someone else", lines: [flat("Theirs", 10)])
        theirs.invoiceSentAt = h.clock
        let all = try h.context.fetch(FetchDescriptor<Proposal>())
        #expect(all.contains { $0 === quote })
        let lines = rows(CSVExport.invoiceLines(all, operatorID: "op"))
        #expect(lines[0] == "Invoice,Client,Status,Created,Service,Place,Quantity,Unit,Unit Price,Line Total")
        let body = Array(lines.dropFirst())
        #expect(body.count == 4)
        #expect(body.contains { $0.hasPrefix("INV-0007,") && $0.hasSuffix(",Edge,,1,each,60.00,60.00") })
        #expect(body.contains { $0.hasPrefix("INV-0009,") && $0.hasSuffix(",Clear,Driveway,1000,sq ft,0.035,35.00") })
        #expect(body.contains { $0.hasPrefix("INV-0009,") && $0.hasSuffix(",Salt,,1,each,75.00,75.00") })
        #expect(body.contains { $0.hasPrefix("INV-0005,") && $0.hasSuffix(",Mow,,1,each,300.00,300.00") })
    }

    /// Money a revision took over from an invoice marked paid is a payment
    /// with no method; it reads "Marked Paid" like the rest.
    @Test func moneyMovedFromAMarkedPaidInvoiceSaysMarkedPaid() throws {
        let h = try Harness(stopCount: 1)
        let revision = Proposal(operatorID: "op", client: h.client)
        revision.invoiceNumber = "INV-0005"
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 40)
        let moved = Payment(amount: 40, method: "", receivedAt: h.clock, operatorID: "op")
        moved.note = "\(InvoiceRecords.impliedPaymentNotePrefix) INV-0004"
        [item].forEach { h.context.insert($0) }
        h.context.insert(moved)
        revision.lineItems = [item]
        revision.payments = [moved]
        h.context.insert(revision)
        let lines = rows(CSVExport.payments([revision], operatorID: "op"))
        #expect(lines.count == 2)
        #expect(lines[1].contains(",40.00,Marked Paid,Marked paid on INV-0004"))
    }

    /// The Payments file lists the money the reports count: an invoice marked
    /// paid with no payment recorded is in it, on the day it was marked paid.
    @Test func paymentsIncludeAnInvoiceMarkedPaidWithoutAPayment() throws {
        let h = try Harness(stopCount: 1)
        func invoice(_ number: String, _ price: Double) -> Proposal {
            let bill = Proposal(operatorID: "op", client: h.client)
            bill.invoiceNumber = number
            let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: price)
            h.context.insert(item)
            bill.lineItems = [item]
            h.context.insert(bill)
            return bill
        }
        let partly = invoice("INV-0010", 100)
        Payments.record(30, method: "Check", note: "#1042", receivedAt: h.clock.addingTimeInterval(-86_400),
                        on: partly, in: h.context, now: h.clock)
        partly.invoicePaidAt = h.clock          // marked paid; $70 never recorded
        let older = invoice("INV-0002", 50)
        older.invoicePaidAt = h.clock.addingTimeInterval(-2 * 86_400)   // before payments were kept
        let documents = [partly, older]
        let lines = rows(CSVExport.payments(documents, operatorID: "op"))
        #expect(lines.count == 4)
        #expect(lines[1].contains(",INV-0002,") && lines[1].contains(",50.00,Marked Paid,"))
        #expect(lines[2].contains(",INV-0010,") && lines[2].contains(",30.00,Check,#1042"))
        #expect(lines[3].contains(",INV-0010,") && lines[3].contains(",70.00,Marked Paid,"))
        // Adds up to the reports' money in.
        let fileTotal = lines.dropFirst().compactMap { line in
            line.split(separator: ",").compactMap { Double($0) }.first
        }.reduce(0, +)
        #expect(abs(fileTotal - Payments.received(documents)) < 0.001)
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
        let theirs = ScheduledVisit(operatorID: "someone else", clientID: "", clientName: "Theirs", clientAddress: "",
                                    scheduledDate: Date(timeIntervalSince1970: 1_850_000_000))
        [later, sooner, theirs].forEach { h.context.insert($0) }
        let lines = rows(CSVExport.schedule([later, sooner, theirs], operatorID: "op", catalog: [service]))
        #expect(lines.count == 3)
        #expect(lines[1].contains("Sooner") && lines[1].contains("Completed"))
        #expect(lines[2].contains("Later") && lines[2].contains("Mowing"))
    }
}
