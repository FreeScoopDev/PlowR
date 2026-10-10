//
//  ProGateTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// What each PlowR Pro gate says, from `Access`: nil lets the action go
/// ahead; otherwise the reason the upgrade sheet gives.
@MainActor
struct ProGateTests {
    private func route(_ name: String, at seconds: TimeInterval, operatorID: String = "op") -> PlowRoute {
        let route = PlowRoute(name: name, operatorID: operatorID)
        route.createdAt = Date(timeIntervalSinceReferenceDate: seconds)
        return route
    }

    // MARK: Adding clients

    @Test func addingAClientStopsAtTheFreeLimit() {
        #expect(ProGate.addClient(Access(plan: .free, clientCount: 9)) == nil)
        #expect(ProGate.addClient(Access(plan: .free, clientCount: 10)) == .clientLimit)
        #expect(ProGate.addClient(Access(plan: .lapsed, clientCount: 10)) == .clientLimit)
        #expect(ProGate.addClient(Access(plan: .pro, clientCount: 500)) == nil)
    }

    @Test func readOnlyIsSaidAsSuch() {
        let readOnly = Access(plan: .lapsed, clientCount: 11)
        #expect(ProGate.addClient(readOnly) == .readOnly)
        #expect(ProGate.createRoute(readOnly, routes: [], operatorID: "op") == .readOnly)
        #expect(ProGate.startRoute(route("Monday", at: 1), access: readOnly, routes: [], operatorID: "op") == .readOnly)
        #expect(ProGate.proFeature("Import Clients", readOnly) == .readOnly)
    }

    @Test func bringingAClientBackIsOneMore() {
        let full = Access(plan: .free, clientCount: 10)
        let inactive = Client(name: "A", phone: "", address: "", operatorID: "op")
        inactive.isActive = false
        #expect(ProGate.bringBack(inactive, full) == .clientLimit)
        #expect(ProGate.bringBack(inactive, Access(plan: .free, clientCount: 9)) == nil)
        #expect(ProGate.bringBack(inactive, Access(plan: .pro, clientCount: 10)) == nil)

        // Already counted: saving them active again isn't one more.
        let current = Client(name: "B", phone: "", address: "", operatorID: "op")
        #expect(ProGate.bringBack(current, full) == nil)
    }

    @Test func lostLeadsCount() {
        // Booking work for a lost lead doesn't clear "lost", so leaving them
        // out was a way past the limit. Only inactive clients are left out.
        let lost = Client(name: "C", phone: "", address: "", operatorID: "op")
        lost.lostAt = .now
        #expect(Access.counts(lost))
        let inactive = Client(name: "D", phone: "", address: "", operatorID: "op")
        inactive.isActive = false
        #expect(!Access.counts(inactive))
    }

    @Test func theFreeTierNoteReopensOnSubscribing() throws {
        let suite = "ProGateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ProStatusBanner.closedKey)
        ProStatusBanner.reopenOnSubscribe(.lapsed, defaults: defaults)
        #expect(defaults.bool(forKey: ProStatusBanner.closedKey))
        ProStatusBanner.reopenOnSubscribe(.pro, defaults: defaults)
        #expect(!defaults.bool(forKey: ProStatusBanner.closedKey))
    }

    // MARK: Changing records

    @Test(arguments: [(Access.Plan.pro, 0), (.pro, 400), (.free, 0), (.free, 30), (.lapsed, 0), (.lapsed, 10)])
    func everyoneButReadOnlyMayChangeRecords(plan: Access.Plan, count: Int) {
        #expect(ProGate.edit(Access(plan: plan, clientCount: count)) == nil)
    }

    @Test func readOnlyMayNotChangeRecords() {
        #expect(ProGate.edit(Access(plan: .lapsed, clientCount: 11)) == .readOnly)
        #expect(ProGate.edit(Access(plan: .lapsed, clientCount: 200)) == .readOnly)
    }

    // MARK: Routes

    @Test func makingASecondRouteNeedsPro() {
        let free = Access(plan: .free, clientCount: 2)
        let monday = route("Monday", at: 1)
        #expect(ProGate.createRoute(free, routes: [], operatorID: "op") == nil)
        #expect(ProGate.createRoute(free, routes: [monday], operatorID: "op") == .routeLimit)
        #expect(ProGate.createRoute(Access(plan: .pro, clientCount: 2), routes: [monday], operatorID: "op") == nil)
    }

    @Test func onlyTheFirstRouteStartsOnTheFreeTier() {
        let free = Access(plan: .lapsed, clientCount: 5)
        let monday = route("Monday", at: 1)
        let tuesday = route("Tuesday", at: 2)
        let routes = [tuesday, monday]
        #expect(ProGate.startRoute(monday, access: free, routes: routes, operatorID: "op") == nil)
        #expect(ProGate.startRoute(tuesday, access: free, routes: routes, operatorID: "op")
                == .notFreeRoute(freeRoute: "Monday"))
        #expect(ProGate.startRoute(tuesday, access: Access(plan: .pro, clientCount: 5),
                                   routes: routes, operatorID: "op") == nil)
    }

    // MARK: Pro tools

    @Test func proToolsSayWhich() {
        #expect(ProGate.proFeature("Import Clients", Access(plan: .free, clientCount: 0)) == .proFeature("Import Clients"))
        #expect(ProGate.proFeature("Import Clients", Access(plan: .pro, clientCount: 0)) == nil)
    }

    // MARK: What the sheet says

    @Test func theSheetNamesTheFreeRouteAndTheLimit() {
        #expect(ProGate.notFreeRoute(freeRoute: "Monday").message.contains("Monday"))
        #expect(ProGate.clientLimit.message.contains("\(Access.freeClientLimit)"))
        #expect(ProGate.proFeature("Import Clients").message.hasPrefix("Import Clients is part of PlowR Pro"))
        // Read only keeps the promise: records, export, payments.
        let readOnly = ProGate.readOnly.message
        #expect(readOnly.contains("export") && readOnly.contains("record payments"))
    }
}
