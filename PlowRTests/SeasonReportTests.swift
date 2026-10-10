//
//  SeasonReportTests.swift
//  PlowRTests
//

import Foundation
import PDFKit
import SwiftData
import Testing
@testable import PlowR

/// The Season Report covers the period chosen, with money to the cent
/// (pre-launch review, 2026-10-10: it covered all time, in whole dollars).
@MainActor
struct SeasonReportTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? .distantPast
    }

    private func visit(_ h: Harness, on day: Date, minutes: Double = 30) -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: UUID().uuidString, source: .route)
        record.clientID = h.client.id.uuidString
        record.performedAt = day
        record.minutes = minutes
        h.context.insert(record)
        return record
    }

    private func invoice(_ h: Harness, total: Double, sent: Date) -> Proposal {
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-\(Int(total))"
        invoice.invoiceSentAt = sent
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        h.context.insert(item)
        h.context.insert(invoice)
        invoice.lineItems = [item]
        return invoice
    }

    @Test func periodsEndNowOrAtTheYearsStart() {
        let now = date(2026, 10, 10)
        let thisYear = SeasonReport.Period.thisYear.interval(now: now, calendar: calendar)
        #expect(calendar.component(.month, from: thisYear.start) == 1 && thisYear.end > now)
        let lastYear = SeasonReport.Period.lastYear.interval(now: now, calendar: calendar)
        #expect(calendar.component(.year, from: lastYear.start) == 2025 && lastYear.end == thisYear.start)
        let twelve = SeasonReport.Period.last12Months.interval(now: now, calendar: calendar)
        #expect(calendar.dateComponents([.month], from: twelve.start, to: now).month == 12)
    }

    // Only what happened in the period: visits, minutes and money received;
    // what's owed is today's.
    @Test func onlyThePeriodCounts() throws {
        let h = try Harness(stopCount: 0)
        let old = visit(h, on: date(2025, 12, 20), minutes: 45)
        let new = visit(h, on: date(2026, 2, 3), minutes: 30)
        let lastWinter = invoice(h, total: 120.50, sent: date(2025, 12, 21))
        Payments.record(120.50, method: "", receivedAt: date(2025, 12, 28), on: lastWinter, in: h.context,
                        now: date(2026, 10, 10))
        let thisWinter = invoice(h, total: 80.25, sent: date(2026, 2, 4))
        let stillOwed = invoice(h, total: 40, sent: date(2025, 11, 1))               // sent before the period
        Payments.record(30.10, method: "", receivedAt: date(2026, 2, 10), on: thisWinter, in: h.context,
                        now: date(2026, 10, 10))
        let period = SeasonReport.Period.thisYear.interval(now: date(2026, 10, 10), calendar: calendar)
        let figures = SeasonReport.figures(clients: [h.client], proposals: [lastWinter, thisWinter, stillOwed],
                                           records: [old, new], period: period, calendar: calendar)
        #expect(figures.visits == 1 && figures.minutes == 30)
        #expect(figures.collected == 30.10)                                        // not last year's 120.50
        #expect(figures.owedNow == 90.15)                                          // today's, older bills too
        #expect(figures.months.count == 1 && figures.months.first?.received == 30.10)
        #expect(figures.clients == [SeasonReport.ClientRow(name: h.client.name, visits: 1, collected: 30.10,
                                                            lastService: date(2026, 2, 3))])
        let all = SeasonReport.figures(clients: [h.client], proposals: [lastWinter, thisWinter, stillOwed], records: [old, new],
                                       period: SeasonReport.Period.allTime.interval(now: date(2026, 10, 10)),
                                       calendar: calendar)
        #expect(all.visits == 2 && all.collected == 150.60)
    }

    // A client with nothing in the period isn't listed.
    @Test func quietClientsArentListed() throws {
        let h = try Harness(stopCount: 0)
        let period = SeasonReport.Period.thisYear.interval(now: date(2026, 10, 10), calendar: calendar)
        let figures = SeasonReport.figures(clients: [h.client], proposals: [], records: [visit(h, on: date(2025, 3, 1))],
                                           period: period, calendar: calendar)
        #expect(figures.clients.isEmpty && figures.clientCount == 0)
    }

    @Test func moneyIsToTheCent() {
        #expect(SeasonReport.money(1234.5) == "$1,234.50")
        #expect(SeasonReport.money(0) == "$0.00")
    }

    @Test func theReportSaysItsPeriodAndCents() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 99.99, sent: h.clock)
        Payments.record(99.99, method: "", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        let data = PDFGenerator.generateSeasonReport(clients: [h.client], proposals: [bill], records: [],
                                                     period: .allTime, profile: nil, reportDate: h.clock.addingTimeInterval(60),
                                                     madeWithPlowR: false)
        let document = try #require(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
            .filter { !$0.isWhitespace }
        #expect(text.contains("AllTime") && text.contains("$99.99"))
    }

    // Last year ends where this year starts: what's after it isn't in it,
    // and midnight on January 1 is this year's.
    @Test func lastYearLeavesThisYearOut() throws {
        let h = try Harness(stopCount: 0)
        let now = date(2026, 10, 10)
        let newYear = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let records = [visit(h, on: date(2025, 6, 1)), visit(h, on: newYear), visit(h, on: date(2026, 3, 1))]
        let bill = invoice(h, total: 50, sent: date(2025, 12, 1))
        Payments.record(50, method: "", receivedAt: newYear, on: bill, in: h.context, now: now)
        let lastYear = SeasonReport.figures(clients: [h.client], proposals: [bill], records: records,
                                            period: SeasonReport.Period.lastYear.interval(now: now, calendar: calendar),
                                            calendar: calendar)
        #expect(lastYear.visits == 1 && lastYear.collected == 0)
        let thisYear = SeasonReport.figures(clients: [h.client], proposals: [bill], records: records,
                                            period: SeasonReport.Period.thisYear.interval(now: now, calendar: calendar),
                                            calendar: calendar)
        #expect(thisYear.visits == 2 && thisYear.collected == 50)
    }

    // A client since removed keeps a row, under the name kept with the
    // records, so the rows add up to the totals.
    @Test func aRemovedClientKeepsARow() throws {
        let h = try Harness(stopCount: 0)
        let record = visit(h, on: date(2026, 3, 1))
        record.clientID = UUID().uuidString
        record.clientName = "Pat (removed)"
        let period = SeasonReport.Period.thisYear.interval(now: date(2026, 10, 10), calendar: calendar)
        let figures = SeasonReport.figures(clients: [h.client], proposals: [], records: [record], period: period,
                                           calendar: calendar)
        #expect(figures.clients.map(\.name) == ["Pat (removed)"] && figures.visits == 1)
    }

    private func pdfText(_ data: Data) throws -> (text: String, pages: Int) {
        let document = try #require(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        return (text.filter { !$0.isWhitespace }, document.pageCount)
    }

    // The title says which dates: last year runs to December 31.
    @Test func lastYearsReportSaysItsDates() throws {
        let h = try Harness(stopCount: 0)
        let data = PDFGenerator.generateSeasonReport(clients: [h.client], proposals: [], records: [],
                                                     period: .lastYear, profile: nil, reportDate: date(2026, 10, 10),
                                                     madeWithPlowR: false)
        let text = try pdfText(data).text
        #expect(text.contains("2025") && text.contains("31"))
        #expect(!text.contains("2026–") && !text.contains("Jan1,2026"))
    }

    // Three years of payments: every month is printed, over as many pages as
    // it takes, and the client table keeps its heading.
    @Test func aLongHistoryFlowsOntoMorePages() throws {
        let h = try Harness(stopCount: 0)
        var invoices: [Proposal] = []
        for k in 0..<36 {
            let day = try #require(calendar.date(byAdding: .month, value: -k, to: date(2026, 9, 15)))
            let bill = invoice(h, total: 10, sent: day)
            Payments.record(10, method: "", receivedAt: day, on: bill, in: h.context, now: date(2026, 10, 10))
            invoices.append(bill)
        }
        let data = PDFGenerator.generateSeasonReport(clients: [h.client], proposals: invoices,
                                                     records: [visit(h, on: date(2026, 9, 1))],
                                                     period: .allTime, profile: nil, reportDate: date(2026, 10, 10),
                                                     madeWithPlowR: false)
        let (text, pages) = try pdfText(data)
        #expect(pages >= 2)
        #expect(text.contains("CLIENTBREAKDOWN"))
        let oldest = try #require(calendar.date(byAdding: .month, value: -35, to: date(2026, 9, 15)))
        #expect(text.contains(oldest.formatted(.dateTime.month(.abbreviated).year()).filter { !$0.isWhitespace }))
    }

    // A client whose money all came in before the period, with no visit in
    // it, has no row.
    @Test func aClientPaidOnlyBeforeThePeriodIsntListed() throws {
        let h = try Harness(stopCount: 0)
        let bill = invoice(h, total: 60, sent: date(2025, 5, 1))
        Payments.record(60, method: "", receivedAt: date(2025, 5, 2), on: bill, in: h.context, now: date(2026, 10, 10))
        let period = SeasonReport.Period.thisYear.interval(now: date(2026, 10, 10), calendar: calendar)
        let figures = SeasonReport.figures(clients: [h.client], proposals: [bill], records: [], period: period,
                                           calendar: calendar)
        #expect(figures.clients.isEmpty && figures.clientCount == 0)
    }

    // Last 12 months starts at the start of that day, as its title says.
    @Test func last12MonthsStartsAtTheStartOfTheDay() throws {
        let afternoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15)))
        let morning = try #require(calendar.date(from: DateComponents(year: 2025, month: 10, day: 10, hour: 9)))
        let period = SeasonReport.Period.last12Months.interval(now: afternoon, calendar: calendar)
        #expect(period.contains(morning))
    }

    // Every page of a free business's report carries the PlowR line, and the
    // client table's heading moves to a new page rather than sit alone.
    @Test func everyPageHasTheLineAndTheTableKeepsItsHeading() throws {
        let h = try Harness(stopCount: 0)
        var invoices: [Proposal] = []
        for k in 0..<21 {
            let day = try #require(calendar.date(byAdding: .month, value: -k, to: date(2026, 9, 15)))
            let bill = invoice(h, total: 10, sent: day)
            Payments.record(10, method: "", receivedAt: day, on: bill, in: h.context, now: date(2026, 10, 10))
            invoices.append(bill)
        }
        let data = PDFGenerator.generateSeasonReport(clients: [h.client], proposals: invoices,
                                                     records: [visit(h, on: date(2026, 9, 1))],
                                                     period: .allTime, profile: nil, reportDate: date(2026, 10, 10),
                                                     madeWithPlowR: true)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 2)
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string?.filter { !$0.isWhitespace } }
        #expect(pages.allSatisfy { $0.contains("PreparedwithPlowR") })
        // The heading is on the same page as the client's row, above it.
        let name = h.client.name.filter { !$0.isWhitespace }
        let page = try #require(pages.first { $0.contains("CLIENTBREAKDOWN") })
        let heading = try #require(page.range(of: "CLIENTBREAKDOWN"))
        #expect(page[heading.upperBound...].contains(name))
    }
}

