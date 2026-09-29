//
//  VisitCalendarTests.swift
//  PlowRTests
//

import EventKit
import Foundation
import Testing
@testable import PlowR

/// What the "PlowR" calendar should hold for a schedule. Earlier versions
/// added an event when a visit was made and never changed it: skipped,
/// moved and deleted visits kept their events and reminders.
@MainActor
struct VisitCalendarTests {
    private let now = Date(timeIntervalSinceReferenceDate: 812_000_040)     // Sept 2026, on the minute
    private var window: DateInterval { VisitCalendar.window(from: now) }

    private func visit(_ name: String = "Pat Doe", in hours: Double = 24, operatorID: String = "op",
                       status: VisitStatus = .scheduled) -> ScheduledVisit {
        let v = ScheduledVisit(operatorID: operatorID, clientID: "c", clientName: name,
                               clientAddress: "1 Main St", scheduledDate: now.addingTimeInterval(hours * 3600))
        v.status = status
        return v
    }

    /// The event PlowR would have made for `visit`.
    private func event(for visit: ScheduledVisit, id: String = "e1", created: Date? = nil) throws -> CalendarEvent {
        CalendarEvent(id: id, visitID: visit.id, details: try #require(VisitCalendar.details(for: visit)),
                      created: created)
    }

    private func changes(_ visits: [ScheduledVisit], _ events: [CalendarEvent],
                         seen: Set<UUID> = []) -> [CalendarChange] {
        VisitCalendar.changes(visits: visits, operatorID: "op", events: events, seen: seen, window: window)
    }

    @Test func aScheduledVisitGetsAnEventWithAReminder() throws {
        let v = visit()
        v.estimatedMinutes = 45
        v.notes = "Gate code 1234"
        let details = try #require(VisitCalendar.details(for: v))
        #expect(details.title == "PlowR: Pat Doe")
        #expect(details.location == "1 Main St")
        #expect(details.notes == "Gate code 1234")
        #expect(details.start == v.scheduledDate)
        #expect(details.end == v.scheduledDate.addingTimeInterval(45 * 60))
        #expect(details.hasReminder)
        #expect(changes([v], []) == [.add(visitID: v.id, details)])
    }

    @Test func aVisitWithNoDurationTakesAnHour() throws {
        let details = try #require(VisitCalendar.details(for: visit()))
        #expect(details.end.timeIntervalSince(details.start) == 3600)
    }

    // A visit added for "now" carries seconds. The event is to the minute, so
    // a calendar that doesn't keep seconds doesn't look changed every sync.
    @Test func theEventStartsOnTheMinute() throws {
        let v = visit(in: 1.5)
        v.scheduledDate = v.scheduledDate.addingTimeInterval(37.25)
        let start = try #require(VisitCalendar.details(for: v)).start
        #expect(start.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) == 0)
        #expect(v.scheduledDate.timeIntervalSince(start) >= 0 && v.scheduledDate.timeIntervalSince(start) < 60)
    }

    @Test func anEventInStepIsLeftAlone() throws {
        let v = visit()
        #expect(changes([v], [try event(for: v)]).isEmpty)
    }

    // Snow day: skip 15 visits and get 15 reminders anyway.
    @Test func skippedAndCancelledVisitsLoseTheirEvents() throws {
        let skipped = visit(), cancelled = visit()
        let events = [try event(for: skipped, id: "a"), try event(for: cancelled, id: "b")]
        skipped.status = .skipped
        cancelled.status = .cancelled
        #expect(VisitCalendar.details(for: skipped) == nil)
        #expect(VisitCalendar.details(for: cancelled) == nil)
        #expect(changes([skipped, cancelled], events) == [.remove(eventID: "a"), .remove(eventID: "b")])
    }

    // Done is a record worth keeping; the reminder isn't.
    @Test func aCompletedVisitKeepsItsEventWithoutTheReminder() throws {
        let v = visit(in: 3)
        let before = try event(for: v)
        v.status = .completed
        let after = try #require(VisitCalendar.details(for: v))
        #expect(!after.hasReminder)
        #expect(changes([v], [before]) == [.update(eventID: "e1", after)])
    }

    @Test func aMovedVisitsEventMovesWithIt() throws {
        let v = visit()
        let before = try event(for: v)
        v.scheduledDate = v.scheduledDate.addingTimeInterval(2 * 86400)
        v.estimatedMinutes = 90
        let moved = try #require(VisitCalendar.details(for: v))
        #expect(changes([v], [before]) == [.update(eventID: "e1", moved)])
    }

    // Seen at the last sync and now gone: deleted, here or on another device.
    @Test func aDeletedVisitsEventIsRemoved() throws {
        let gone = visit()
        #expect(changes([], [try event(for: gone)], seen: [gone.id]) == [.remove(eventID: "e1")])
    }

    // An iCloud calendar is on the user's other devices too. An event another
    // device added for a visit this one hasn't received yet must stay, or the
    // two devices would take turns adding and removing it.
    @Test func anEventForAVisitNotReceivedYetIsLeftAlone() throws {
        #expect(changes([], [try event(for: visit())], seen: []).isEmpty)
    }

    @Test func onlyTheSignedInBusinessesVisitsHaveEvents() throws {
        let mine = visit("Mine"), theirs = visit("Theirs", operatorID: "someone-else")
        let result = changes([mine, theirs], [try event(for: theirs, id: "theirs")])
        #expect(result == [.remove(eventID: "theirs"),
                           .add(visitID: mine.id, try #require(VisitCalendar.details(for: mine)))])
    }

    // Two devices adding the same visit's event at once: every device keeps
    // the oldest, so they agree.
    @Test func aSecondEventForAVisitIsRemovedKeepingTheOldest() throws {
        let v = visit()
        let old = try event(for: v, id: "z-old", created: now.addingTimeInterval(-60))
        let new = try event(for: v, id: "a-new", created: now)
        #expect(changes([v], [new, old]) == [.remove(eventID: "a-new")])
    }

    @Test func eventsPlowRDidntAddAreNeverTouched() throws {
        let mine = CalendarEvent(id: "user", visitID: nil,
                                 details: EventDetails(title: "Dentist", location: "", notes: "", start: now,
                                                       end: now.addingTimeInterval(3600), hasReminder: false),
                                 created: nil)
        #expect(changes([], [mine], seen: []).isEmpty)
    }

    @Test func theWindowIsTheLastMonthAndTheNextSixMonths() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        #expect(window.start == calendar.date(byAdding: .month, value: -1, to: today))
        #expect(window.end == calendar.date(byAdding: .month, value: 6, to: today))
    }

    // A repeating visit runs two years ahead; only the next six months go in.
    @Test func aVisitPastTheWindowGetsNoEventUntilItsInside() throws {
        let far = visit(in: 24 * 250)
        #expect(changes([far], []).isEmpty)
        let later = VisitCalendar.window(from: now.addingTimeInterval(86400 * 100))
        #expect(VisitCalendar.changes(visits: [far], operatorID: "op", events: [], seen: [], window: later)
            == [.add(visitID: far.id, try #require(VisitCalendar.details(for: far)))])
    }

    @Test func aVisitMovedOutOfTheWindowLosesItsEvent() throws {
        let v = visit()
        let before = try event(for: v)
        v.scheduledDate = now.addingTimeInterval(86400 * 400)
        #expect(changes([v], [before]) == [.remove(eventID: "e1")])
    }

    // A removal that failed is tried again: the visit stays seen while its
    // event is there, even after it leaves the window's visits.
    @Test func aVisitStaysSeenWhileItsEventIsThere() throws {
        let gone = visit(), kept = visit("Kept")
        let events = [try event(for: gone)]
        let seen = VisitCalendar.seen(visits: [kept], events: events, before: [gone.id], window: window)
        #expect(seen == [kept.id, gone.id])
        #expect(VisitCalendar.seen(visits: [kept], events: [], before: seen, window: window) == [kept.id])
    }

    // The window leaves out its end: a calendar search does too.
    @Test func aVisitAtTheWindowsEndIsOutside() throws {
        let edge = visit()
        edge.scheduledDate = window.end
        #expect(!VisitCalendar.isIn(window, window.end))
        #expect(VisitCalendar.isIn(window, window.start))
        #expect(changes([edge], []).isEmpty)
    }

    // An overnight run begun before the window is a record, like every event
    // the window has moved past, not a visit moved out of it.
    @Test func anEventBegunBeforeTheWindowIsKept() throws {
        let overnight = visit()
        overnight.scheduledDate = window.start.addingTimeInterval(-30 * 60)
        #expect(changes([overnight], [try event(for: overnight)], seen: [overnight.id]).isEmpty)
    }

    @Test func anOldEventForAVisitMovedIntoTheWindowMoves() throws {
        let v = visit()
        v.scheduledDate = window.start.addingTimeInterval(-30 * 60)
        let old = try event(for: v)
        v.scheduledDate = now.addingTimeInterval(86400)
        #expect(changes([v], [old]) == [.update(eventID: "e1", try #require(VisitCalendar.details(for: v)))])
    }

    // Created at the same moment (or undated): the tie goes by the ID that's
    // the same on every device, so every device keeps the same event.
    @Test func aTieGoesByTheSharedID() throws {
        let v = visit()
        var first = try event(for: v, id: "a-local")
        first.sharedID = "z-shared"
        var second = try event(for: v, id: "b-local")
        second.sharedID = "y-shared"
        #expect(changes([v], [first, second]) == [.remove(eventID: "a-local")])
    }

    // iCloud can give text back with other line endings or trimmed spaces.
    @Test func textTheCalendarTidiedIsntAChange() throws {
        let v = visit()
        v.notes = "Gate code\n1234"
        var tidied = try event(for: v)
        tidied.details.notes = "Gate code\r\n1234 \n"
        tidied.details.location = " 1 Main St"
        #expect(changes([v], [tidied]).isEmpty)
        tidied.details.notes = "Gate code 9999"
        #expect(changes([v], [tidied]).count == 1)
    }

    // Removing everything searches every year in spans EventKit accepts.
    @Test func theSearchCoversEveryYearWithoutGaps() {
        let spans = VisitCalendar.allTime
        #expect(spans.first?.start ?? .distantFuture <= Date(timeIntervalSinceReferenceDate: 599_529_600))
        #expect(spans.last?.end ?? .distantPast >= Date(timeIntervalSinceReferenceDate: 3_124_137_600))
        for (a, b) in zip(spans, spans.dropFirst()) { #expect(a.end == b.start) }
        #expect(spans.allSatisfy { $0.duration <= 4 * 365 * 86400 })
    }

    // The privacy policy: client details stay on the device and in iCloud.
    // A "PlowR" calendar in Google or Exchange is never used.
    @Test func onlyICloudAndThisDeviceHoldTheCalendar() {
        #expect(EventKitVisitCalendarStore.isOwnAccount(type: .local, title: "Default"))
        #expect(EventKitVisitCalendarStore.isOwnAccount(type: .calDAV, title: "iCloud"))
        #expect(!EventKitVisitCalendarStore.isOwnAccount(type: .calDAV, title: "Google"))
        #expect(!EventKitVisitCalendarStore.isOwnAccount(type: .exchange, title: "Work"))
        #expect(!EventKitVisitCalendarStore.isOwnAccount(type: .subscribed, title: "Holidays"))
    }

    @Test func theLinkNamesTheVisit() throws {
        let id = UUID()
        #expect(VisitCalendar.visitID(fromLink: VisitCalendar.link(for: id)) == id)
        #expect(VisitCalendar.visitID(fromLink: URL(string: "https://example.com/visit/\(id.uuidString)")) == nil)
        #expect(VisitCalendar.visitID(fromLink: URL(string: "plowr://activeRoute")) == nil)
        #expect(VisitCalendar.visitID(fromLink: nil) == nil)
    }
}
