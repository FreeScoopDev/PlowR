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
        #expect(calendar.component(.month, from: thisYear.start) == 1 && thisYear.end == now)
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
        Payments.record(30.10, method: "", receivedAt: date(2026, 2, 10), on: thisWinter, in: h.context,
                        now: date(2026, 10, 10))
        let period = SeasonReport.Period.thisYear.interval(now: date(2026, 10, 10), calendar: calendar)
        let figures = SeasonReport.figures(clients: [h.client], proposals: [lastWinter, thisWinter],
                                           records: [old, new], period: period, calendar: calendar)
        #expect(figures.visits == 1 && figures.minutes == 30)
        #expect(figures.collected == 30.10)                                        // not last year's 120.50
        #expect(figures.owedNow == 50.15)
        #expect(figures.months.count == 1 && figures.months.first?.received == 30.10)
        #expect(figures.clients == [SeasonReport.ClientRow(name: h.client.name, visits: 1, collected: 30.10,
                                                            lastService: date(2026, 2, 3))])
        let all = SeasonReport.figures(clients: [h.client], proposals: [lastWinter, thisWinter], records: [old, new],
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
}
