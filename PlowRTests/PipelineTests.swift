//
//  PipelineTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import PlowR

/// Where a client stands before they're a customer, worked out from what's on file.
@MainActor
struct PipelineTests {
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func client(_ h: Harness, _ name: String, added: Date? = nil) -> Client {
        let client = Client(name: name, phone: "", address: "", operatorID: "op")
        if let added { client.createdAt = added }
        h.context.insert(client)
        return client
    }

    private func proposal(_ h: Harness, for client: Client, total: Double = 250, invoice: Bool = false) -> Proposal {
        let document = Proposal(operatorID: "op", client: client)
        if invoice { document.invoiceNumber = "INV-0001" }
        let item = ProposalLineItem(serviceName: "Cleanup", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        h.context.insert(item)
        h.context.insert(document)
        document.lineItems = [item]
        return document
    }

    private var facts: (Harness) -> Pipeline.Facts { { Pipeline.Facts(in: $0.context) } }

    @Test func aClientsStageComesFromWhatsOnFile() throws {
        let h = try Harness(stopCount: 0)
        let lead = client(h, "Lead")
        let quoted = client(h, "Quoted")
        _ = proposal(h, for: quoted)
        let invoiced = client(h, "Invoiced")
        _ = proposal(h, for: invoiced, invoice: true)
        let worked = client(h, "Worked")
        let job = ServiceRecord(operatorID: "op", sourceKey: "manual:x", source: .manual)
        job.clientID = worked.id.uuidString
        h.context.insert(job)
        let visited = client(h, "Visited")
        visited.totalVisits = 3
        let facts = facts(h)
        #expect(Pipeline.stage(of: lead, facts: facts) == .lead)
        #expect(Pipeline.stage(of: quoted, facts: facts) == .quoted)
        #expect(Pipeline.stage(of: invoiced, facts: facts) == .customer)          // a quote turned into an invoice
        #expect(Pipeline.stage(of: worked, facts: facts) == .customer)
        #expect(Pipeline.stage(of: visited, facts: facts) == .customer)
    }

    @Test func lostIsSetAndUndoneButWorkMakesThemACustomer() throws {
        let h = try Harness(stopCount: 0)
        let quoted = client(h, "Quoted")
        _ = proposal(h, for: quoted)
        Pipeline.setLost(true, for: quoted, in: h.context, now: h.clock)
        #expect(quoted.lostAt == h.clock)
        #expect(Pipeline.stage(of: quoted, facts: facts(h)) == .lost)
        Pipeline.setLost(false, for: quoted, in: h.context)
        #expect(Pipeline.stage(of: quoted, facts: facts(h)) == .quoted)
        Pipeline.setLost(true, for: quoted, in: h.context, now: h.clock)
        quoted.totalVisits = 1                                                    // came back and booked work
        #expect(Pipeline.stage(of: quoted, facts: facts(h)) == .customer)
    }

    @Test func aQuoteWaitingFiveDaysIsDueAFollowUp() throws {
        let h = try Harness(stopCount: 0)
        let waiting = client(h, "Waiting")
        _ = proposal(h, for: waiting)
        waiting.lastMessageSentAt = h.clock.addingTimeInterval(-5 * day)
        let recent = client(h, "Recent")
        _ = proposal(h, for: recent)
        recent.lastMessageSentAt = h.clock.addingTimeInterval(-4 * day)
        let answered = client(h, "Answered")
        _ = proposal(h, for: answered)
        answered.lastMessageSentAt = h.clock.addingTimeInterval(-9 * day)
        answered.clientRespondedAt = h.clock.addingTimeInterval(-8 * day)
        let leadSent = client(h, "Lead")                                          // no proposal: nothing to follow up
        leadSent.lastMessageSentAt = h.clock.addingTimeInterval(-9 * day)

        let entries = Pipeline.entries([waiting, recent, answered, leadSent], operatorID: "op", facts: facts(h),
                                       now: h.clock)
        #expect(entries.filter(\.needsFollowUp).map(\.client.name) == ["Waiting"])
        #expect(entries.first { $0.client.name == "Answered" }?.waitingDays == nil)
        #expect(entries.first { $0.client.name == "Waiting" }?.quoteTotal == 250)
    }

    @Test func thePipelineIsThisBusinesssActiveClientsNotCustomers() throws {
        let h = try Harness(stopCount: 0)
        let newer = client(h, "Newer", added: h.clock)
        let older = client(h, "Older", added: h.clock.addingTimeInterval(-day))
        let customer = client(h, "Customer")
        customer.totalVisits = 2
        let inactive = client(h, "Inactive")
        inactive.isActive = false
        let others = client(h, "Theirs")
        others.operatorID = "someone-else"
        let entries = Pipeline.entries([older, newer, customer, inactive, others], operatorID: "op",
                                       facts: facts(h), now: h.clock)
        #expect(entries.map(\.client.name) == ["Newer", "Older"])                // newest first
    }

    // Agreed and booked, not served yet (a seasonal contract before the
    // first storm): a customer, not a quote to chase.
    @Test func workBookedMakesThemACustomer() throws {
        let h = try Harness(stopCount: 1)
        let scheduled = client(h, "Scheduled")
        _ = proposal(h, for: scheduled)
        let visit = ScheduledVisit(operatorID: "op", clientID: scheduled.id.uuidString, clientName: "", clientAddress: "",
                                   scheduledDate: h.clock.addingTimeInterval(30 * day))
        h.context.insert(visit)
        let cancelledOnly = client(h, "Cancelled")
        let cancelled = ScheduledVisit(operatorID: "op", clientID: cancelledOnly.id.uuidString, clientName: "",
                                       clientAddress: "", scheduledDate: h.clock)
        cancelled.status = .cancelled
        h.context.insert(cancelled)
        let facts = facts(h)
        #expect(Pipeline.stage(of: scheduled, facts: facts) == .customer)
        #expect(Pipeline.stage(of: h.client, facts: facts) == .customer)          // a stop on a route
        #expect(Pipeline.stage(of: cancelledOnly, facts: facts) == .lead)
        #expect(Pipeline.stage(of: scheduled, facts: Pipeline.Facts(of: scheduled, in: h.context)) == .customer)
        #expect(Pipeline.stage(of: h.client, facts: Pipeline.Facts(of: h.client, in: h.context)) == .customer)
    }

    // Lost in March, sent a new proposal in October: quoted again.
    @Test func aProposalAfterLostPutsThemBackInQuoted() throws {
        let h = try Harness(stopCount: 0)
        let back = client(h, "Back")
        let old = proposal(h, for: back)
        old.createdAt = h.clock.addingTimeInterval(-200 * day)
        Pipeline.setLost(true, for: back, in: h.context, now: h.clock.addingTimeInterval(-190 * day))
        #expect(Pipeline.stage(of: back, facts: facts(h)) == .lost)
        let new = proposal(h, for: back)
        new.createdAt = h.clock
        #expect(Pipeline.stage(of: back, facts: facts(h)) == .quoted)
    }

    @Test func aReplyAtTheMomentOfSendingIsAReply() throws {
        let h = try Harness(stopCount: 0)
        let replied = client(h, "Replied")
        replied.lastMessageSentAt = h.clock
        replied.clientRespondedAt = h.clock
        #expect(!Pipeline.isAwaitingResponse(replied))
        replied.clientRespondedAt = nil
        #expect(Pipeline.isAwaitingResponse(replied))
    }

    // The reminder is dated for the day the quote has waited 5 days, at
    // 9 AM; one already due goes to the next 9 AM; lost or answered, none.
    @Test func eachQuoteIsRemindedOnItsFollowUpDay() throws {
        let h = try Harness(stopCount: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 14)))
        func quoted(_ name: String, sentDaysAgo: Double) -> Client {
            let c = client(h, name)
            _ = proposal(h, for: c)
            c.lastMessageSentAt = now.addingTimeInterval(-sentDaysAgo * day)
            return c
        }
        let soon = quoted("Soon", sentDaysAgo: 3)
        let due = quoted("Due", sentDaysAgo: 7)
        let lost = quoted("Lost", sentDaysAgo: 7)
        Pipeline.setLost(true, for: lost, in: h.context, now: now)
        let answered = quoted("Answered", sentDaysAgo: 7)
        answered.clientRespondedAt = now
        let entries = Pipeline.entries([soon, due, lost, answered], operatorID: "op", facts: facts(h), now: now)
        let dates = Dictionary(uniqueKeysWithValues: Pipeline.followUpDates(entries, now: now, calendar: calendar)
            .map { ($0.client.name, $0.date) })
        #expect(dates.keys.sorted() == ["Due", "Soon"])
        #expect(dates["Soon"] == calendar.date(from: DateComponents(year: 2027, month: 1, day: 12, hour: 9)))
        #expect(dates["Due"] == calendar.date(from: DateComponents(year: 2027, month: 1, day: 11, hour: 9)))

        let requests = FollowUpReminders.requests([(soon, try #require(dates["Soon"]))], calendar: calendar)
        #expect(requests.map(\.identifier) == ["follow_up_" + soon.id.uuidString])
        #expect(requests.first?.content.title == "Follow Up with Soon")
        let trigger = try #require(requests.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.day == 12 && trigger.dateComponents.hour == 9)
    }
}
