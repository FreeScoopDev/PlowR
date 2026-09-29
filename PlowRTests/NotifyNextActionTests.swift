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
        #expect(reply == .init(text: "Opening a text to Client 0.", stopID: h.route.sortedStops[0].id))
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
