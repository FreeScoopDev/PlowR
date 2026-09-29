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
            Proposal.self, ProposalLineItem.self, StopPhoto.self,
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
        ClientRemoval.deactivate(pat, in: context)
        #expect(!pat.isActive)
        #expect(monday.sortedStops.map(\.clientName) == ["Sam Roe", "Salt shed"])
        #expect(tuesday.sortedStops.isEmpty)
        #expect(try ClientStops.of(pat, in: context).isEmpty)
        #expect(!context.hasChanges)                          // saved
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

    @Test func deletingKeepsRecordsWhenAsked() throws {
        visit(pat, .scheduled)                                // to do: deleted
        visit(pat, .scheduled, daysFromNow: -3)               // missed, still to do: deleted
        visit(pat, .completed, daysFromNow: -7)
        visit(pat, .skipped, daysFromNow: -14)
        visit(sam, .scheduled)
        document(pat, invoice: true)
        document(pat)
        photo(pat)
        ClientRemoval.delete(pat, keepingRecords: true, in: context)
        #expect(try count(Client.self) == 1)
        #expect(try count(RouteStop.self) == 2)               // Sam's and the salt shed
        let visits = try context.fetch(FetchDescriptor<ScheduledVisit>())
        #expect(visits.filter { $0.clientID == pat.id.uuidString }.map(\.status).sorted { $0.rawValue < $1.rawValue }
                == [.completed, .skipped])
        #expect(visits.contains { $0.clientID == sam.id.uuidString })
        #expect(try count(Proposal.self) == 2)
        #expect(try count(ProposalLineItem.self) == 2)
        #expect(try count(StopPhoto.self) == 1)
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
        ClientRemoval.delete(pat, keepingRecords: false, in: context)
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
        visit(pat, .completed, daysFromNow: -7)
        visit(pat, .cancelled, daysFromNow: -8)
        document(pat)
        document(pat, invoice: true)
        photo(pat)
        visit(sam, .scheduled)
        #expect(ClientRemoval.footprint(of: pat, in: context) == .init(
            routeNames: ["Monday", "Tuesday"], visitsToDo: 1, documents: 2, pastVisits: 2, photos: 1))
        #expect(ClientRemoval.footprint(of: sam, in: context) == .init(routeNames: ["Monday"], visitsToDo: 1))
    }

    @Test func theDeletePromptSaysWhatGoesAndWhatCanStay() {
        let full = ClientRemoval.Footprint(routeNames: ["Monday", "Tuesday"], visitsToDo: 2,
                                          documents: 3, pastVisits: 1, photos: 4)
        #expect(ClientRemoval.deleteMessage(for: full, isActive: true) == "They'll be taken off 2 routes: Monday and Tuesday. "
            + "2 visits not yet done will be deleted. "
            + "Keep their 3 invoices and proposals, 1 past visit, and 4 photos for your records, or delete everything? "
            + "To keep the client too, mark them Inactive instead.")
        let bare = ClientRemoval.Footprint(routeNames: ["Monday"], visitsToDo: 1, documents: 1)
        #expect(ClientRemoval.deleteMessage(for: bare, isActive: false) == "They'll be taken off the route Monday. "
            + "1 visit not yet done will be deleted. "
            + "Keep their 1 invoice or proposal for your records, or delete everything?")
        #expect(ClientRemoval.deleteMessage(for: .init(), isActive: true) == "To keep the client too, mark them Inactive instead.")
        #expect(!ClientRemoval.Footprint(routeNames: ["Monday"], visitsToDo: 3).hasRecords)
    }

    @Test func theInactivePromptSaysWhichRoutes() {
        #expect(ClientRemoval.deactivateMessage(for: .init(routeNames: ["Monday", "Tuesday"]))
            == "They'll be taken off 2 routes: Monday and Tuesday. Marking them active again won't put them back.")
    }
}
