//
//  AccessibilityAndWordingTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The rules behind the 2026-11-24 accessibility pass: what the Documents
/// tab's badge counts, and how many past-due visits Schedule shows.
@MainActor
struct AccessibilityAndWordingTests {
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func document(_ h: Harness, operatorID: String = "op", invoice: Bool = true,
                          sent: Bool = false, dueDaysAgo: Double? = nil, paid: Bool = false,
                          voided: Bool = false) -> Proposal {
        let document = Proposal(operatorID: operatorID, client: h.client)
        if invoice { document.invoiceNumber = "INV-\(Int.random(in: 1_000...9_999))" }
        document.invoiceSentAt = sent ? h.clock.addingTimeInterval(-100 * day) : nil
        document.invoiceDueDate = dueDaysAgo.map { h.clock.addingTimeInterval(-$0 * day) }
        if paid { document.invoicePaidAt = h.clock }
        if voided { document.voidedAt = h.clock }
        h.context.insert(document)
        return document
    }

    // The badge is what needs action now: overdue invoices, not drafts (they
    // kept it lit all the time), and only this business's.
    @Test func documentsBadgeCountsOnlyOverdue() throws {
        let h = try Harness(stopCount: 0)
        let docs = [
            document(h),                                             // draft invoice
            document(h, invoice: false),                             // proposal
            document(h, sent: true, dueDaysAgo: -5),                 // sent, not due yet
            document(h, sent: true, dueDaysAgo: 3),                  // overdue
            document(h, sent: true, dueDaysAgo: 40),                 // overdue
            document(h, sent: true, dueDaysAgo: 3, paid: true),      // paid
            document(h, sent: true, dueDaysAgo: 3, voided: true),    // void
            document(h, operatorID: "other", sent: true, dueDaysAgo: 3) // another business's
        ]
        #expect(DocumentsBadge.count(docs, operatorID: "op", now: h.clock) == 2)
        #expect(DocumentsBadge.count([document(h), document(h)], operatorID: "op", now: h.clock) == 0)
    }

    // Past Due shows three, and Show All the rest; no Show All with three or fewer.
    @Test func pastDueShowsThreeUntilShowAll() {
        let five = [1, 2, 3, 4, 5]
        #expect(PastDueList.shown(five, showingAll: false) == [1, 2, 3])
        #expect(PastDueList.hiddenCount(five, showingAll: false) == 2)
        #expect(PastDueList.shown(five, showingAll: true) == five)
        #expect(PastDueList.hiddenCount(five, showingAll: true) == 0)
        #expect(PastDueList.shown([1, 2, 3], showingAll: false) == [1, 2, 3])
        #expect(PastDueList.hiddenCount([1, 2, 3], showingAll: false) == 0)
        #expect(PastDueList.hiddenCount([Int](), showingAll: false) == 0)
    }
}
