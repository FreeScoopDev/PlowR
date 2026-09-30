//
//  ClientRemovalTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A client marked inactive, or deleted, comes off their routes. Deleting
/// used to leave their stops on every route (the prompt said they'd be
/// removed) and their visits on the schedule.
@MainActor
struct ClientRemovalTests {
    /// Kept: a container that goes away resets its context, and every model
    /// in it is destroyed.
    let container: ModelContainer
    let context: ModelContext
    let pat: Client
    let sam: Client
    let monday: PlowRoute
    let tuesday: PlowRoute

    init() throws {
        container = try ModelContainer(
            for: Client.self, PlowRoute.self, RouteStop.self, ScheduledVisit.self,
            Proposal.self, ProposalLineItem.self, StopPhoto.self, ServiceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = container.mainContext
        pat = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
        sam = Client(name: "Sam Roe", phone: "555-0200", address: "2 Elm St", operatorID: "op")
        monday = PlowRoute(name: "Monday", operatorID: "op")
        tuesday = PlowRoute(name: "Tuesday", operatorID: "op")
        for model in [pat, sam, monday, tuesday] as [any PersistentModel] { context.insert(model) }
        add(RouteStop(order: 0, client: pat), to: monday)
        add(RouteStop(order: 1, client: sam), to: monday)
        add(RouteStop(order: 2, customName: "Salt shed", customAddress: "9 Depot Rd"), to: monday)
        add(RouteStop(order: 0, client: pat), to: tuesday)
        add(RouteStop(order: 1, client: pat), to: tuesday)        // twice on one route
        try context.save()
    }

    private func add(_ stop: RouteStop, to route: PlowRoute) {
        stop.route = route
        context.insert(stop)
    }

    @discardableResult
    private func visit(_ client: Client, _ status: VisitStatus, daysFromNow days: Double = 1) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: client.id.uuidString, clientName: client.name,
                                   clientAddress: client.address, scheduledDate: Date().addingTimeInterval(days * 86_400))
        visit.status = status
        context.insert(visit)
        return visit
    }

    private func logWork(_ client: Client) {
        let record = ServiceRecord(operatorID: "op", sourceKey: "visit:\(UUID().uuidString)", source: .visit)
        record.clientID = client.id.uuidString
        context.insert(record)
    }

    @discardableResult
    private func document(_ client: Client, invoice: Bool = false) -> Proposal {
        let proposal = Proposal(operatorID: "op", client: client)
        if invoice { proposal.invoiceNumber = "INV-1001" }
        let line = ProposalLineItem(serviceName: "Mowing", zoneLabel: "Front", quantity: 1, unitType: "flat", unitPrice: 40)
        context.insert(proposal)
        context.insert(line)
        proposal.lineItems = [line]
        return proposal
    }

    @discardableResult
    private func photo(_ client: Client) -> StopPhoto {
        let photo = StopPhoto(operatorID: "op", clientID: client.id.uuidString, routeID: "", isBefore: true, imageData: Data([1]))
        context.insert(photo)
        return photo
    }

    private func count<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    // MARK: - Inactive

    @Test func markingInactiveTakesThemOffEveryRoute() throws {
        ClientRemoval.setActive(false, for: pat, in: context)
        #expect(!pat.isActive)
        #expect(monday.sortedStops.map(\.clientName) == ["Sam Roe", "Salt shed"])
        #expect(tuesday.sortedStops.isEmpty)
        #expect(try ClientStops.of(pat, in: context).isEmpty)
        #expect(!context.hasChanges)                          // saved
    }

    // Marking them active again doesn't put them back, and an active client
    // marked active keeps their stops.
    @Test func markingActiveTakesNothingOffAndPutsNothingBack() throws {
        ClientRemoval.setActive(true, for: pat, in: context)
        #expect(try ClientStops.of(pat, in: context).count == 3)
        ClientRemoval.setActive(false, for: pat, in: context)
        ClientRemoval.setActive(true, for: pat, in: context)
        #expect(pat.isActive)
        #expect(try ClientStops.of(pat, in: context).isEmpty)
        #expect(!context.hasChanges)
    }

    // Clients marked inactive before that took them off routes come off
    // once, at the first launch of this version; not again.
    @Test func alreadyInactiveClientsComeOffRoutesOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "ClientRemovalTests-\(UUID().uuidString)"))
        pat.isActive = false                                  // the old way: still on routes
        try context.save()
        #expect(ClientRemoval.takeInactiveClientsOffRoutes(in: context, defaults: defaults) == 3)
        #expect(try ClientStops.of(pat, in: context).isEmpty)
        #expect(try ClientStops.of(sam, in: context).count == 1)
        #expect(!context.hasChanges)                          // saved
        sam.isActive = false                                  // say, by an older PlowR on another device
        #expect(ClientRemoval.takeInactiveClientsOffRoutes(in: context, defaults: defaults) == 0)
        #expect(try ClientStops.of(sam, in: context).count == 1)
    }

    // A new phone before iCloud has brought the clients: not done yet, so
    // the next launch still cleans up.
    @Test func anEmptyStoreDoesntCountAsCleanedUp() throws {
        let defaults = try #require(UserDefaults(suiteName: "ClientRemovalTests-\(UUID().uuidString)"))
        let empty = try ModelContainer(
            for: Client.self, PlowRoute.self, RouteStop.self, ScheduledVisit.self,
            Proposal.self, ProposalLineItem.self, StopPhoto.self, ServiceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        #expect(ClientRemoval.takeInactiveClientsOffRoutes(in: empty.mainContext, defaults: defaults) == 0)
        #expect(!defaults.bool(forKey: ClientRemoval.inactiveCleanupKey))
        pat.isActive = false
        try context.save()
        #expect(ClientRemoval.takeInactiveClientsOffRoutes(in: context, defaults: defaults) == 3)
        #expect(defaults.bool(forKey: ClientRemoval.inactiveCleanupKey))
    }

    @Test func takingOffRoutesLeavesTheirRecords() throws {
        visit(pat, .scheduled)
        document(pat)
        photo(pat)
        #expect(ClientRemoval.takeOffRoutes(pat, in: context) == 3)
        #expect(try count(ScheduledVisit.self) == 1)
        #expect(try count(Proposal.self) == 1)
        #expect(try count(StopPhoto.self) == 1)
        #expect(try count(Client.self) == 2)
    }

    // MARK: - Delete

    // Routes don't mark visits complete: a visit done from a route is still
    // "scheduled". What's dated in the past is history either way.
    @Test func visitsAheadAreThoseDatedFromNowOnAndNotCompleted() {
        let now = Date()
        #expect(ClientRemoval.isAhead(visit(pat, .scheduled, daysFromNow: 1), now: now))
        #expect(ClientRemoval.isAhead(visit(pat, .cancelled, daysFromNow: 7), now: now))
        #expect(!ClientRemoval.isAhead(visit(pat, .completed, daysFromNow: 1), now: now))
        #expect(!ClientRemoval.isAhead(visit(pat, .scheduled, daysFromNow: -3), now: now))
        #expect(!ClientRemoval.isAhead(visit(pat, .skipped, daysFromNow: -14), now: now))
        let atNow = visit(pat, .scheduled)
        atNow.scheduledDate = now
        #expect(ClientRemoval.isAhead(atNow, now: now))
    }

    // A kept visit is history: marking it complete doesn't add the next
    // visit of its series for a client who's gone.
    @Test func aKeptVisitDoesntContinueItsSeries() throws {
        let past = visit(pat, .scheduled, daysFromNow: -7)
        let next = visit(pat, .scheduled, daysFromNow: 0.5)
        for weekly in [past, next] {
            weekly.isRecurring = true
            weekly.recurrenceType = .weekly
            weekly.seriesID = "weekly"
        }
        #expect(past.continuation(among: [past]) != nil)        // how it would continue
        ClientRemoval.delete(pat, keepingRecords: true, in: context)
        let kept = try context.fetch(FetchDescriptor<ScheduledVisit>())
        #expect(kept.count == 1)
        #expect(kept.first?.continuation(among: kept) == nil)
    }

    @Test func deletingKeepsRecordsWhenAsked() throws {
        visit(pat, .scheduled)                                // ahead: deleted
        visit(pat, .cancelled, daysFromNow: 7)                // ahead: deleted
        visit(pat, .scheduled, daysFromNow: -3)               // done from a route: kept
        visit(pat, .completed, daysFromNow: -7)
        visit(pat, .skipped, daysFromNow: -14)
        visit(sam, .scheduled)
        logWork(pat)                                          // the Service Log: kept
        document(pat, invoice: true)
        document(pat)
        photo(pat)                                            // only their page shows it: deleted
        photo(sam)
        ClientRemoval.delete(pat, keepingRecords: true, in: context)
        #expect(try context.fetch(FetchDescriptor<ServiceRecord>()).map(\.clientID) == [pat.id.uuidString])
        #expect(try count(Client.self) == 1)
        #expect(try count(RouteStop.self) == 2)               // Sam's and the salt shed
        let visits = try context.fetch(FetchDescriptor<ScheduledVisit>())
        #expect(visits.filter { $0.clientID == pat.id.uuidString }.map(\.status.rawValue).sorted()
                == [VisitStatus.completed, .scheduled, .skipped].map(\.rawValue).sorted())
        #expect(visits.contains { $0.clientID == sam.id.uuidString })
        #expect(try count(Proposal.self) == 2)
        #expect(try count(ProposalLineItem.self) == 2)
        #expect(try context.fetch(FetchDescriptor<StopPhoto>()).map(\.clientID) == [sam.id.uuidString])
        #expect(!context.hasChanges)
    }

    @Test func deletingEverythingLeavesOtherClientsAlone() throws {
        visit(pat, .completed, daysFromNow: -7)
        visit(pat, .scheduled)
        visit(sam, .completed, daysFromNow: -7)
        document(pat, invoice: true)
        document(sam)
        photo(pat)
        photo(sam)
        logWork(pat)
        logWork(sam)
        ClientRemoval.delete(pat, keepingRecords: false, in: context)
        #expect(try context.fetch(FetchDescriptor<ServiceRecord>()).map(\.clientID) == [sam.id.uuidString])
        #expect(try context.fetch(FetchDescriptor<Client>()).map(\.name) == ["Sam Roe"])
        #expect(try context.fetch(FetchDescriptor<ScheduledVisit>()).map(\.clientName) == ["Sam Roe"])
        #expect(try context.fetch(FetchDescriptor<Proposal>()).map(\.clientName) == ["Sam Roe"])
        #expect(try count(ProposalLineItem.self) == 1)
        #expect(try context.fetch(FetchDescriptor<StopPhoto>()).map(\.clientID) == [sam.id.uuidString])
        #expect(monday.sortedStops.map(\.clientName) == ["Sam Roe", "Salt shed"])
        #expect(tuesday.sortedStops.isEmpty)
    }

    // MARK: - What the prompts say

    @Test func theFootprintCountsWhatRemovalTouches() {
        visit(pat, .scheduled)
        visit(pat, .scheduled, daysFromNow: -2)
        visit(pat, .completed, daysFromNow: -7)
        visit(pat, .cancelled, daysFromNow: -8)
        document(pat)
        document(pat, invoice: true)
        photo(pat)
        visit(sam, .scheduled)
        #expect(ClientRemoval.footprint(of: pat, in: context) == .init(
            routeNames: ["Monday", "Tuesday"], visitsAhead: 1, documents: 2, pastVisits: 3, photos: 1))
        #expect(ClientRemoval.footprint(of: sam, in: context) == .init(routeNames: ["Monday"], visitsAhead: 1))
    }

    private let us = Locale(identifier: "en_US")

    @Test func theDeletePromptSaysWhatGoesAndWhatCanStay() {
        let full = ClientRemoval.Footprint(routeNames: ["Monday", "Tuesday"], visitsAhead: 2,
                                          documents: 3, pastVisits: 1, photos: 4)
        #expect(ClientRemoval.deleteMessage(for: full, isActive: true, locale: us)
            == "They'll be taken off 2 routes: Monday and Tuesday. "
            + "Their 2 upcoming visits and 4 photos will be deleted with them. "
            + "Keep their 3 invoices or proposals and 1 past visit for your records, or delete everything? "
            + "To keep them and their history, mark them Inactive instead: that takes them off their routes too.")
        let one = ClientRemoval.Footprint(routeNames: ["Monday"], visitsAhead: 1, documents: 1)
        #expect(ClientRemoval.deleteMessage(for: one, isActive: false, locale: us)
            == "They'll be taken off the route Monday. "
            + "Their 1 upcoming visit will be deleted with them. "
            + "Keep their 1 invoice or proposal for your records, or delete everything?")
        #expect(ClientRemoval.deleteMessage(for: .init(photos: 1), isActive: false, locale: us)
            == "Their 1 photo will be deleted with them. This can't be undone.")
        #expect(ClientRemoval.deleteMessage(for: .init(), isActive: false, locale: us) == "This can't be undone.")
        #expect(ClientRemoval.deleteMessage(for: .init(), isActive: true, locale: us)
            == "This can't be undone. To keep them and their history, mark them Inactive instead.")
    }

    // Photos can't be kept: only the client's page shows them.
    @Test func onlyDocumentsAndPastVisitsAreRecordsToKeep() {
        #expect(!ClientRemoval.Footprint(routeNames: ["Monday"], visitsAhead: 3, photos: 2).hasRecords)
        #expect(ClientRemoval.Footprint(documents: 1).hasRecords)
        #expect(ClientRemoval.Footprint(pastVisits: 1).hasRecords)
    }

    @Test func theInactivePromptSaysWhichRoutes() {
        #expect(ClientRemoval.deactivateMessage(for: .init(routeNames: ["Monday", "Tuesday"]), locale: us)
            == "They'll be taken off 2 routes: Monday and Tuesday. Marking them active again won't put them back.")
    }
}
