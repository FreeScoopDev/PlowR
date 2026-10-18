//
//  MoneyOwedTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Money owed by how late it is.
@MainActor
struct MoneyOwedTests {
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func invoice(_ h: Harness, total: Double, dueDaysAgo: Double?, sent: Bool = true,
                         client: Client? = nil) -> Proposal {
        let invoice = Proposal(operatorID: "op", client: client ?? h.client)
        invoice.invoiceNumber = "INV-\(Int.random(in: 1_000...9_999))"
        invoice.invoiceSentAt = sent ? h.clock.addingTimeInterval(-100 * day) : nil
        invoice.invoiceDueDate = dueDaysAgo.map { h.clock.addingTimeInterval(-$0 * day) }
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        h.context.insert(item)
        h.context.insert(invoice)
        invoice.lineItems = [item]
        return invoice
    }

    // Late by calendar day: due earlier today isn't late, due late last night is.
    @Test func dueEarlierTodayIsNotLate() throws {
        let h = try Harness(stopCount: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        func on(_ d: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2027, month: 1, day: d, hour: hour, minute: minute)) ?? .distantPast
        }
        let now = on(15, 15)
        let today = invoice(h, total: 10, dueDaysAgo: nil)
        today.invoiceDueDate = on(15, 0, 5)
        #expect(MoneyOwed.age(of: today, now: now, calendar: calendar) == .notDue)
        #expect(today.invoiceStatus(now: now, calendar: calendar) == .sent)
        let yesterday = invoice(h, total: 10, dueDaysAgo: nil)
        yesterday.invoiceDueDate = on(14, 23, 59)
        #expect(MoneyOwed.age(of: yesterday, now: now, calendar: calendar) == .upTo30)
        #expect(yesterday.invoiceStatus(now: now, calendar: calendar) == .overdue)
        // The reminder text says so too (the property reads today's date).
        today.invoiceDueDate = Calendar.current.startOfDay(for: .now)
        #expect(today.invoiceStatus == .sent && today.reminderMessage().contains("outstanding"))
        today.invoiceDueDate = Calendar.current.startOfDay(for: .now).addingTimeInterval(-1)
        #expect(today.invoiceStatus == .overdue && today.reminderMessage().contains("overdue"))
    }

    @Test func lateCountsFromTheDueDate() throws {
        let h = try Harness(stopCount: 0)
        func age(_ days: Double?, sent: Bool = true) -> MoneyOwed.Age {
            MoneyOwed.age(of: invoice(h, total: 10, dueDaysAgo: days, sent: sent), now: h.clock)
        }
        #expect(age(-5) == .notDue)                                               // due in 5 days
        #expect(age(nil) == .notDue)                                              // no due date
        #expect(age(40, sent: false) == .notDue)                                  // a draft
        #expect(age(0) == .notDue)                                                // due today isn't late
        #expect(age(0.05) == .notDue)                                             // an hour earlier today
        #expect(age(1) == .upTo30)                                                // late from the next day
        #expect(age(30) == .upTo30)
        #expect(age(31) == .upTo60)
        #expect(age(60) == .upTo60)
        #expect(age(61) == .upTo90)
        #expect(age(91) == .over90)
    }

    @Test func eachAgeAndEachClientAddUpToTheTotalOwed() throws {
        let h = try Harness(stopCount: 0)
        let bo = Client(name: "Bo", phone: "", address: "", operatorID: "op")
        h.context.insert(bo)
        let partly = invoice(h, total: 100, dueDaysAgo: 45)
        Payments.record(40, method: "", receivedAt: h.clock, on: partly, in: h.context, now: h.clock)
        _ = invoice(h, total: 50, dueDaysAgo: -3)
        let paid = invoice(h, total: 70, dueDaysAgo: 100)
        paid.invoicePaidAt = h.clock
        _ = invoice(h, total: 200, dueDaysAgo: 5, client: bo)                     // owes more, but less late
        let others = invoice(h, total: 999, dueDaysAgo: 200)                      // another business's
        others.operatorID = "someone-else"

        let summary = MoneyOwed.summary(try h.context.fetch(FetchDescriptor<Proposal>()), operatorID: "op", now: h.clock)
        #expect(summary.byAge[.notDue] == 50)
        #expect(summary.byAge[.upTo30] == 200)
        #expect(summary.byAge[.upTo60] == 60)                                     // the balance, not the total
        #expect(summary.byAge[.over90] == 0)                                      // paid, or not this business's
        #expect(summary.total == 310)
        #expect(summary.clients.map(\.name) == [h.client.name, "Bo"])            // the latest payer first
        #expect(summary.clients.first?.owed == 110)
        #expect(summary.clients.first?.oldest == .upTo60)
        #expect(summary.clients.first?.invoices.first === partly)                 // most overdue first
    }
}
