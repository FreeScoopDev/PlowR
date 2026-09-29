//
//  NotifyNextActionTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Siri's "Notify next client": a text to the client you're driving to, and
/// nothing marked complete. It used to open the route screen's prompt, whose
/// Send and Skip complete the current stop.
@MainActor
struct NotifyNextActionTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func siri(_ store: ActiveRouteStore) -> NotifyNextAction.Reply {
        NotifyNextAction.siri(in: store, role: UserRole.business)
    }

    /// A route whose clients all have phone numbers.
    private func harnessWithPhones() throws -> Harness {
        let h = try Harness()
        for stop in h.route.sortedStops { stop.clientPhone = "555-0100" }
        return h
    }

    @Test func itTextsTheCurrentStopAndCompletesNothing() throws {
        let h = try harnessWithPhones()
        let store = h.makeStore()
        store.start(h.route)
        let reply = siri(store)
        #expect(reply == .init(text: "Opening a text to Client 0, your current stop.", stopID: h.route.sortedStops[0].id))
        #expect(store.currentStopIndex == 0)
        #expect(h.clients.allSatisfy { $0.totalVisits == 0 })
        #expect(h.route.sortedStops.allSatisfy { $0.actualMinutes == 0 })
    }

    // Said after "Complete current stop": the client you're now driving to.
    @Test func afterACompletionItTextsTheNextClient() throws {
        let h = try harnessWithPhones()
        let store = h.makeStore()
        store.start(h.route)
        _ = CompleteStopAction.siri(in: store, role: UserRole.business)
        #expect(siri(store).stopID == h.route.sortedStops[1].id)
        #expect(store.currentStopIndex == 1)
    }

    @Test func withNoRouteItSaysSo() throws {
        let h = try harnessWithPhones()
        #expect(siri(h.makeStore()) == .init(text: "No route is in progress.", stopID: nil))
    }

    @Test func onceEveryStopIsDoneThereIsNoOneToText() throws {
        let h = try Harness(stopCount: 1)
        h.route.sortedStops[0].clientPhone = "555-0100"
        let store = h.makeStore()
        store.start(h.route)
        _ = CompleteStopAction.siri(in: store, role: UserRole.business)
        #expect(siri(store) == .init(text: "Every stop on this route is already done.", stopID: nil))
    }

    @Test func aClientWithNoPhoneNumberIsSaid() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        #expect(siri(store) == .init(text: "Client 0 has no phone number in PlowR.", stopID: nil))
    }

    // The route was deleted on another device while PlowR was closed: the
    // store only finds out when it checks, which Siri makes it do.
    @Test func aRouteDeletedWhileClosedIsntTexted() throws {
        let h = try harnessWithPhones()
        let before = h.makeClosedAppStore()
        before.start(h.route)
        h.context.delete(h.route)
        try h.context.save()
        #expect(siri(h.makeStore()) == .init(text: "No route is in progress.", stopID: nil))
    }

    // Siri checks the route itself: iCloud can remove it before the app has
    // heard (the store then still holds it).
    @Test func aRouteGoneBeforeTheAppHeardIsntTexted() throws {
        let h = try harnessWithPhones()
        var gone = false
        let store = h.makeStore(fetchRoutes: { context in
            gone ? [] : try context.fetch(FetchDescriptor<PlowRoute>())
        })
        store.start(h.route)
        gone = true
        #expect(siri(store) == .init(text: "No route is in progress.", stopID: nil))
        #expect(!store.isActive)
    }

    // A request held behind another sheet opens only if its stop is still
    // the current one: completed meanwhile, it would offer to text a client
    // already done.
    @Test func aHeldRequestOpensOnlyForTheCurrentStop() throws {
        let h = try harnessWithPhones()
        let store = h.makeStore()
        store.start(h.route)
        let now = Date()
        let first = h.route.sortedStops[0]
        let request = NotifyNextAction.Request(stopID: first.id, at: now)
        #expect(NotifyNextAction.stopToOpen(request, in: store, now: now)?.id == first.id)
        _ = store.completeCurrentStop(expecting: first.id)
        #expect(NotifyNextAction.stopToOpen(request, in: store, now: now) == nil)
    }

    @Test func anOldRequestIsDropped() throws {
        let h = try harnessWithPhones()
        let store = h.makeStore()
        store.start(h.route)
        let now = Date()
        let request = NotifyNextAction.Request(stopID: h.route.sortedStops[0].id, at: now)
        let late = now.addingTimeInterval(NotifyNextAction.requestLifetime + 1)
        #expect(NotifyNextAction.stopToOpen(request, in: store, now: late) == nil)
        #expect(NotifyNextAction.stopToOpen(nil, in: store, now: now) == nil)
    }

    // Client mode or no role chosen: no route of its own.
    @Test func onlyABusinessTexts() throws {
        let h = try harnessWithPhones()
        let store = h.makeStore()
        store.start(h.route)
        for role in ["client", "", nil] as [String?] {
            #expect(NotifyNextAction.siri(in: store, role: role).stopID == nil)
        }
    }
}
