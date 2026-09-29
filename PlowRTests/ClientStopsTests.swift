//
//  ClientStopsTests.swift
//  PlowRTests
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A client's route stops follow the client. They kept the name, phone,
/// address and pin copied when the stop was made, so a corrected address or
/// phone number never reached the routes the client was already on.
@MainActor
struct ClientStopsTests {
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
            for: Client.self, PlowRoute.self, RouteStop.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = container.mainContext
        pat = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
        pat.latitude = 43.37
        pat.longitude = -72.34
        sam = Client(name: "Sam Roe", phone: "555-0200", address: "2 Elm St", operatorID: "op")
        monday = PlowRoute(name: "Monday", operatorID: "op")
        tuesday = PlowRoute(name: "Tuesday", operatorID: "op")
        for model in [pat, sam] as [any PersistentModel] { context.insert(model) }
        context.insert(monday)
        context.insert(tuesday)
        add(RouteStop(order: 0, client: pat), to: monday)
        add(RouteStop(order: 1, client: sam), to: monday)
        add(RouteStop(order: 2, customName: "Salt shed", customAddress: "9 Depot Rd"), to: monday)
        add(RouteStop(order: 0, client: pat), to: tuesday)
        try context.save()
    }

    private func add(_ stop: RouteStop, to route: PlowRoute) {
        stop.route = route
        context.insert(stop)
    }

    private func stops(of client: Client) throws -> [RouteStop] {
        try ClientStops.of(client, in: context)
    }

    @Test func aChangedClientIsChangedOnEveryRoute() throws {
        pat.name = "Pat Doe-Smith"
        pat.phone = "555-0111"
        pat.address = "12 Pleasant St"
        pat.latitude = 43.38
        pat.longitude = -72.35
        ClientStops.update(for: pat)
        let patStops = try stops(of: pat)
        #expect(patStops.count == 2)
        for stop in patStops {
            #expect(stop.clientName == "Pat Doe-Smith")
            #expect(stop.clientPhone == "555-0111")
            #expect(stop.clientAddress == "12 Pleasant St")
            #expect(stop.latitude == 43.38)
            #expect(stop.longitude == -72.35)
        }
    }

    @Test func otherClientsAndCustomStopsAreLeftAlone() throws {
        pat.address = "12 Pleasant St"
        ClientStops.update(for: pat)
        let samStop = try #require(try stops(of: sam).first)
        #expect(samStop.clientAddress == "2 Elm St")
        let custom = try #require(monday.sortedStops.first { $0.isCustomStop })
        #expect(custom.clientName == "Salt shed")
        #expect(custom.clientAddress == "9 Depot Rd")
    }

    // The stop's own notes and what a run recorded are the stop's, not the client's.
    @Test func aStopsOwnDetailsStay() throws {
        let stop = try #require(try stops(of: pat).first)
        stop.stopNotes = "Gate code 1234"
        stop.equipmentNotes = "Blade"
        stop.actualMinutes = 12
        stop.completedServiceIDs = ["plow"]
        pat.phone = "555-0111"
        ClientStops.update(for: pat)
        #expect(stop.stopNotes == "Gate code 1234")
        #expect(stop.equipmentNotes == "Blade")
        #expect(stop.actualMinutes == 12)
        #expect(stop.completedServiceIDs == ["plow"])
        #expect(stop.clientPhone == "555-0111")
    }

    // Nothing is written, so nothing is sent to iCloud, for a stop already
    // in step.
    @Test func anUnchangedStopIsntWritten() throws {
        let stop = try #require(try stops(of: pat).first)
        #expect(!ClientStops.follow(stop, pat))
        #expect(!context.hasChanges)
        pat.phone = "555-0111"
        #expect(ClientStops.follow(stop, pat))
        #expect(!ClientStops.follow(stop, pat))
        ClientStops.update(for: pat)              // pat's other stop
        try context.save()
        ClientStops.update(for: pat)
        ClientStops.updateAll(in: context)
        #expect(!context.hasChanges)
    }

    // At launch: stops that fell behind (made before stops followed their
    // client, or changed on a device with an older PlowR) catch up.
    @Test func staleStopsCatchUpAtLaunch() throws {
        let stale = try #require(try stops(of: sam).first)
        stale.clientPhone = "old"
        stale.clientAddress = "old"
        pat.address = "12 Pleasant St"            // changed without update(for:)
        ClientStops.updateAll(in: context)
        #expect(stale.clientPhone == "555-0200")
        #expect(stale.clientAddress == "2 Elm St")
        #expect(try stops(of: pat).allSatisfy { $0.clientAddress == "12 Pleasant St" })
        #expect(!context.hasChanges)             // saved
    }

    // A client changed on another device arrives through iCloud: the stops
    // follow then, not only at the next launch. A route app stays open for
    // days.
    @Test func stopsFollowWhenICloudBringsChanges() throws {
        let center = NotificationCenter()
        let observer = ClientStops.followRemoteChanges(of: container, center: center)
        defer { center.removeObserver(observer) }
        pat.phone = "555-0111"                    // changed without update(for:)
        try context.save()
        #expect(try stops(of: pat).allSatisfy { $0.clientPhone == "555-0100" })
        center.post(name: .NSPersistentStoreRemoteChange, object: nil)
        #expect(try stops(of: pat).allSatisfy { $0.clientPhone == "555-0111" })
        #expect(!context.hasChanges)             // saved
    }
}
