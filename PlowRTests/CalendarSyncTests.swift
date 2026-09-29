//
//  CalendarSyncTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Calendars in memory, standing in for EventKit (tests can't be given
/// calendar access). Like the real one, several "PlowR" calendars are one.
@MainActor
final class FakeVisitCalendarStore: VisitCalendarStore {
    var access: CalendarAccess = .full
    /// What the permission prompt answers.
    var grants = true
    var requests = 0
    /// PlowR's calendars, the one new events go in first.
    var calendars: [String] = []
    var events: [CalendarEvent] = []
    /// Which calendar each event is in; "PlowR" when not set.
    var calendarOf: [String: String] = [:]
    var applyFails = false
    /// A removal that "works" but leaves the event, as EventKit does when it
    /// can't find the event it was given.
    var removalsDontTake = false
    private(set) var remembersCalendar = false
    private var next = 0

    var hasCalendar: Bool { !calendars.isEmpty }

    func requestFullAccess() async -> Bool {
        requests += 1
        if grants { access = .full }
        return grants
    }

    func events(in span: DateInterval, create: Bool) throws -> [CalendarEvent]? {
        if calendars.isEmpty {
            guard create else { return nil }
            calendars = ["PlowR"]
            remembersCalendar = true
        }
        return events.filter { $0.details.end > span.start && $0.details.start < span.end }
    }

    func apply(_ changes: [CalendarChange]) throws {
        if applyFails { throw CocoaError(.fileWriteUnknown) }
        if calendars.isEmpty {
            calendars = ["PlowR"]
            remembersCalendar = true
        }
        for change in changes {
            switch change {
            case let .add(visitID, details):
                next += 1
                events.append(CalendarEvent(id: "event-\(next)", visitID: visitID, details: details,
                                            created: Date(timeIntervalSinceReferenceDate: Double(next))))
                calendarOf["event-\(next)"] = calendars[0]
            case let .update(id, details):
                if let i = events.firstIndex(where: { $0.id == id }) { events[i].details = details }
            case let .remove(id):
                if !removalsDontTake { events.removeAll { $0.id == id } }
            }
        }
    }

    func removeEmptyCalendars(searching spans: [DateInterval]) throws {
        calendars.removeAll { calendar in
            !events.contains { event in
                (calendarOf[event.id] ?? "PlowR") == calendar
                    && spans.contains { event.details.end > $0.start && event.details.start < $0.end }
            }
        }
        if calendars.isEmpty { remembersCalendar = false }
    }

    /// PlowR's events, by visit.
    var visitIDs: [UUID] { events.compactMap(\.visitID) }
}

@MainActor
struct CalendarSyncTests {
    private let now = Date(timeIntervalSinceReferenceDate: 812_000_000)     // Sept 2026

    /// A schedule, a calendar and a sync, signed in as "op".
    @MainActor
    final class Setup {
        let store = FakeVisitCalendarStore()
        let suite = "CalendarSyncTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        let now: Date
        private(set) var sync: CalendarSync

        init(now: Date, delay: Duration = .seconds(2)) throws {
            self.now = now
            defaults = try #require(UserDefaults(suiteName: suite))
            container = try ModelContainer(for: Schema(PlowRApp.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
            sync = CalendarSync(store: store, defaults: defaults, now: { now }, delay: delay)
            sync.configure(context: container.mainContext)
            sync.operatorID = "op"
        }

        /// The app opened again: a new sync reading the same preferences.
        func relaunch() {
            sync = CalendarSync(store: store, defaults: defaults, now: { [now] in now }, delay: .seconds(2))
            sync.configure(context: context)
            sync.operatorID = "op"
        }

        @discardableResult
        func visit(_ name: String = "Pat Doe", inDays days: Double = 1, operatorID: String = "op") throws -> ScheduledVisit {
            let v = ScheduledVisit(operatorID: operatorID, clientID: "c", clientName: name, clientAddress: "1 Main St",
                                   scheduledDate: now.addingTimeInterval(days * 86400))
            context.insert(v)
            try context.save()
            return v
        }

        deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    @Test func offUntilTurnedOn() throws {
        let s = try Setup(now: now)
        try s.visit()
        #expect(!s.sync.isEnabled)
        s.sync.syncNow()
        #expect(!s.store.hasCalendar)
        #expect(s.store.events.isEmpty)
    }

    @Test func turningOnAsksForFullAccessAndAddsTheVisits() async throws {
        let s = try Setup(now: now)
        s.store.access = .canAsk
        let visit = try s.visit()
        await s.sync.setEnabled(true)
        #expect(s.store.requests == 1)
        #expect(s.sync.isEnabled)
        #expect(!s.sync.needsAccess)
        #expect(s.store.visitIDs == [visit.id])
        #expect(s.store.events.first?.details == VisitCalendar.details(for: visit))
    }

    @Test func refusedAccessLeavesItOffAndSaysSo() async throws {
        let s = try Setup(now: now)
        s.store.access = .canAsk
        s.store.grants = false
        try s.visit()
        await s.sync.setEnabled(true)
        #expect(!s.sync.isEnabled)
        #expect(s.sync.needsAccess)
        #expect(s.store.events.isEmpty)
        #expect(!s.sync.isAsking)
    }

    // Denied before: iOS won't show the prompt again, only Settings can change it.
    @Test func deniedAccessIsNotAskedForAgain() async throws {
        let s = try Setup(now: now)
        s.store.access = .denied
        await s.sync.setEnabled(true)
        #expect(s.store.requests == 0)
        #expect(!s.sync.isEnabled)
        #expect(s.sync.needsAccess)
    }

    @Test func theSwitchIsRememberedAfterARelaunch() async throws {
        let s = try Setup(now: now)
        await s.sync.setEnabled(true)
        s.relaunch()
        #expect(s.sync.isEnabled)
        let later = try s.visit("Later")
        s.sync.syncNow()
        #expect(s.store.visitIDs == [later.id])
    }

    // Skip 15 visits on a snow day and get 15 reminders anyway: not now.
    @Test func skippingMovingAndDeletingAVisitChangeItsEvent() async throws {
        let s = try Setup(now: now)
        let skipped = try s.visit("Skipped"), moved = try s.visit("Moved"), deleted = try s.visit("Deleted")
        await s.sync.setEnabled(true)
        #expect(s.store.events.count == 3)

        skipped.status = .skipped
        moved.scheduledDate = moved.scheduledDate.addingTimeInterval(3 * 86400)
        s.context.delete(deleted)
        try s.context.save()
        s.sync.syncNow()

        #expect(s.store.visitIDs == [moved.id])
        #expect(s.store.events.first?.details.start == VisitCalendar.details(for: moved)?.start)
    }

    @Test func onlyTheSignedInBusinessesVisitsAreAdded() async throws {
        let s = try Setup(now: now)
        let mine = try s.visit("Mine")
        try s.visit("Theirs", operatorID: "someone-else")
        await s.sync.setEnabled(true)
        #expect(s.store.visitIDs == [mine.id])
    }

    // At launch the sign-in is checked with Apple first. A sync before that
    // answer would see no business and remove every event.
    @Test func nothingIsChangedWhileNoOneIsSignedIn() async throws {
        let s = try Setup(now: now)
        try s.visit()
        await s.sync.setEnabled(true)
        #expect(s.store.events.count == 1)
        s.relaunch()
        s.sync.operatorID = ""
        s.sync.syncNow()
        #expect(s.store.events.count == 1)
    }

    @Test func turningOffRemovesPlowRsEventsAndItsCalendar() async throws {
        let s = try Setup(now: now)
        try s.visit()
        try s.visit("Other", inDays: 5)
        await s.sync.setEnabled(true)
        #expect(s.store.events.count == 2)
        await s.sync.setEnabled(false)
        #expect(!s.sync.isEnabled)
        #expect(s.store.events.isEmpty)
        #expect(!s.store.hasCalendar)
    }

    // An event the user put in the PlowR calendar keeps the calendar.
    @Test func turningOffKeepsTheUsersOwnEvents() async throws {
        let s = try Setup(now: now)
        try s.visit()
        await s.sync.setEnabled(true)
        let theirs = CalendarEvent(id: "dentist", visitID: nil,
                                   details: EventDetails(title: "Dentist", location: "", notes: "", start: now,
                                                         end: now.addingTimeInterval(3600), hasReminder: false),
                                   created: nil)
        s.store.events.append(theirs)
        await s.sync.setEnabled(false)
        #expect(s.store.events == [theirs])
        #expect(s.store.hasCalendar)
    }

    // Old events are a record while sync is on, but turning it off removes
    // everything PlowR added, not only what's in the window.
    @Test func turningOffRemovesOldEventsToo() async throws {
        let s = try Setup(now: now)
        await s.sync.setEnabled(true)
        let old = try #require(VisitCalendar.details(for: ScheduledVisit(
            operatorID: "op", clientID: "c", clientName: "Old", clientAddress: "",
            scheduledDate: now.addingTimeInterval(-200 * 86400))))
        s.store.events.append(CalendarEvent(id: "old", visitID: UUID(), details: old, created: nil))
        await s.sync.setEnabled(false)
        #expect(s.store.events.isEmpty)
    }

    // A swipe, an edit, an iCloud import: all of them save, and every save
    // brings the calendar in step. No screen calls the sync.
    @Test func aSaveBringsTheCalendarInStep() async throws {
        let s = try Setup(now: now, delay: .milliseconds(20))
        await s.sync.setEnabled(true)
        let visit = try s.visit()
        try await waitUntil { s.store.visitIDs == [visit.id] }
        visit.status = .skipped
        try s.context.save()
        try await waitUntil { s.store.events.isEmpty }
    }

    // Leaving the app syncs from memory: autosave may not have run yet.
    @Test func changesNotSavedYetAreSynced() async throws {
        let s = try Setup(now: now)
        await s.sync.setEnabled(true)
        let visit = ScheduledVisit(operatorID: "op", clientID: "c", clientName: "Unsaved", clientAddress: "",
                                   scheduledDate: now.addingTimeInterval(86400))
        s.context.insert(visit)
        #expect(s.context.hasChanges)
        s.sync.syncNow()
        #expect(s.store.visitIDs == [visit.id])
    }

    @Test func accessTakenAwayInSettingsIsShownAndNothingIsWritten() async throws {
        let s = try Setup(now: now)
        await s.sync.setEnabled(true)
        s.store.access = .denied
        s.sync.refresh()
        #expect(s.sync.needsAccess)
        try s.visit()
        s.sync.syncNow()
        #expect(s.store.events.isEmpty)
        // Given back: the switch is still on, and the next sync catches up.
        s.store.access = .full
        s.sync.refresh()
        #expect(!s.sync.needsAccess)
        s.sync.syncNow()
        #expect(s.store.events.count == 1)
    }

    @Test func aFailedSyncIsShownUntilOneWorks() async throws {
        let s = try Setup(now: now)
        await s.sync.setEnabled(true)
        s.store.applyFails = true
        try s.visit()
        s.sync.syncNow()
        #expect(s.sync.problem != nil)
        s.store.applyFails = false
        s.sync.syncNow()
        #expect(s.sync.problem == nil)
        #expect(s.store.events.count == 1)
    }

    // A sync that fails changes nothing, the seen visits included, so a
    // deleted visit's event is still removed by the next one.
    @Test func aRemovalThatFailedIsTriedAgain() async throws {
        let s = try Setup(now: now)
        let gone = try s.visit()
        await s.sync.setEnabled(true)
        s.context.delete(gone)
        try s.context.save()
        s.store.applyFails = true
        s.sync.syncNow()
        s.store.applyFails = false
        s.sync.syncNow()
        #expect(s.store.events.isEmpty)
    }

    @Test func deleteAccountRemovesTheCalendarAndTurnsSyncOff() async throws {
        let s = try Setup(now: now)
        try s.visit()
        await s.sync.setEnabled(true)
        try s.sync.eraseAll()
        #expect(s.store.events.isEmpty)
        #expect(!s.store.hasCalendar)
        #expect(!s.sync.isEnabled)
        // Signing in again doesn't bring it back.
        s.sync.operatorID = "someone-new"
        try s.visit()
        s.sync.syncNow()
        #expect(s.store.events.isEmpty)
    }

    // Turned off earlier, but events could be left if removing them failed then.
    @Test func deleteAccountRemovesEventsEvenWithTheSwitchOff() async throws {
        let s = try Setup(now: now)
        try s.visit()
        await s.sync.setEnabled(true)
        s.store.applyFails = true
        await s.sync.setEnabled(false)
        #expect(s.store.events.count == 1)
        s.store.applyFails = false
        try s.sync.eraseAll()
        #expect(s.store.events.isEmpty)
    }

    // A removal can "work" and leave the event (EventKit skips an event it
    // can't find). The visit stays seen while its event is there, so the
    // next sync removes it; forgotten, it would stay for good.
    @Test func anEventThatOutlivedItsRemovalIsRemovedNextTime() async throws {
        let s = try Setup(now: now)
        let gone = try s.visit()
        await s.sync.setEnabled(true)
        s.context.delete(gone)
        try s.context.save()
        s.store.removalsDontTake = true
        s.sync.syncNow()
        #expect(s.store.events.count == 1)
        s.store.removalsDontTake = false
        s.sync.syncNow()
        #expect(s.store.events.isEmpty)
    }

    // A reinstall starts with nothing seen. An event for a visit this device
    // has, moved out of the window, still goes.
    @Test func afterAReinstallAMovedVisitsEventIsRemoved() async throws {
        let s = try Setup(now: now)
        let visit = try s.visit()
        await s.sync.setEnabled(true)
        s.defaults.removeObject(forKey: CalendarSync.seenKey)
        visit.scheduledDate = now.addingTimeInterval(400 * 86400)
        try s.context.save()
        s.relaunch()
        s.sync.syncNow()
        #expect(s.store.events.isEmpty)
    }

    // Today + 6 months is midnight, and a visit added on a tapped day with no
    // time chosen is at midnight. A calendar search leaves out an event that
    // starts right at the end, so it was added again on every sync.
    @Test func aVisitAtTheWindowsEndDoesntPileUp() async throws {
        let s = try Setup(now: now)
        await s.sync.setEnabled(true)
        let edge = ScheduledVisit(operatorID: "op", clientID: "c", clientName: "Edge", clientAddress: "",
                                  scheduledDate: VisitCalendar.window(from: now).end)
        s.context.insert(edge)
        try s.context.save()
        s.sync.syncNow()
        s.sync.syncNow()
        #expect(s.store.events.count <= 1)
    }

    // Two devices turned sync on before either's calendar reached the other:
    // two "PlowR" calendars, with the same visit in each. This covers the
    // rules and the store's contract; which EventKit calendars count is
    // plowRCalendarIDs (VisitCalendarTests).
    @Test func twoPlowRCalendarsAreTreatedAsOne() async throws {
        let s = try Setup(now: now)
        let visit = try s.visit()
        await s.sync.setEnabled(true)
        let first = try #require(s.store.events.first)
        s.store.calendars.append("PlowR (iPad)")
        var copy = first
        copy.id = "from-the-ipad"
        copy.created = now
        s.store.events.append(copy)
        s.store.calendarOf[copy.id] = "PlowR (iPad)"
        s.sync.syncNow()
        #expect(s.store.events.map(\.id) == [first.id])
        #expect(s.store.visitIDs == [visit.id])
        // Both go on the way out.
        await s.sync.setEnabled(false)
        #expect(s.store.calendars.isEmpty)
    }

    // Turned off in the Settings app, calendar access can't remove the
    // calendar: Delete Account said everything was gone while every client's
    // name and address stayed in iCloud.
    @Test func deleteAccountWithoutCalendarAccessSaysSoOnce() async throws {
        let s = try Setup(now: now)
        try s.visit()
        await s.sync.setEnabled(true)
        s.store.access = .denied
        #expect(throws: CalendarOutOfReach.self) { try s.sync.eraseAll() }
        #expect(s.store.events.count == 1)
        // Asked again, it goes ahead: the user may have deleted it by hand.
        try s.sync.eraseAll()
    }

    @Test func deleteAccountWithoutAccessButNoCalendarIsFine() throws {
        let s = try Setup(now: now)
        s.store.access = .denied
        try s.sync.eraseAll()
    }

    @Test func turningOffWithoutCalendarAccessSaysSo() async throws {
        let s = try Setup(now: now)
        try s.visit()
        await s.sync.setEnabled(true)
        s.store.access = .denied
        await s.sync.setEnabled(false)
        #expect(!s.sync.isEnabled)
        #expect(s.sync.problem != nil)
        #expect(s.store.events.count == 1)
        // Access given back: the removal it owed happens when the app comes back.
        s.store.access = .full
        s.sync.refresh()
        #expect(s.store.events.isEmpty)
        #expect(!s.store.hasCalendar)
        #expect(s.sync.problem == nil)
    }

    // Removing a calendar removes everything in it, in every year: it's
    // removed only if nothing of the user's is left, however far ahead.
    @Test func turningOffKeepsACalendarWithTheUsersEventYearsAhead() async throws {
        let s = try Setup(now: now)
        try s.visit()
        await s.sync.setEnabled(true)
        let later = now.addingTimeInterval(2 * 365 * 86400)
        s.store.events.append(CalendarEvent(id: "wedding", visitID: nil,
                                            details: EventDetails(title: "Wedding", location: "", notes: "",
                                                                  start: later, end: later.addingTimeInterval(3600),
                                                                  hasReminder: false),
                                            created: nil))
        await s.sync.setEnabled(false)
        #expect(s.store.events.map(\.id) == ["wedding"])
        #expect(s.store.hasCalendar)
    }

    // Records stay while sync is on; turning it off removes them, from years back too.
    @Test func turningOffRemovesRecordsFromYearsBack() async throws {
        let s = try Setup(now: now)
        await s.sync.setEnabled(true)
        let old = now.addingTimeInterval(-4.5 * 365 * 86400)
        s.store.events.append(CalendarEvent(id: "2022", visitID: UUID(),
                                            details: EventDetails(title: "PlowR: Old", location: "", notes: "",
                                                                  start: old, end: old.addingTimeInterval(3600),
                                                                  hasReminder: false),
                                            created: nil))
        await s.sync.setEnabled(false)
        #expect(s.store.events.isEmpty)
        #expect(!s.store.hasCalendar)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {      // Up to 5 s on a busy CI runner.
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
