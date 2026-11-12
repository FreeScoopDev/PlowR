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
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
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

    // MARK: - Route Notes

    // A gate code changed on the client's page reaches every route they're
    // on: the stops used to keep the notes copied when they were made.
    @Test func routeNotesFollowToEveryStop() throws {
        pat.defaultStopNotes = "Gate 1234"
        ClientStops.update(for: pat)
        #expect(try stops(of: pat).allSatisfy { $0.placeNotes == "Gate 1234" })
        let samStop = try #require(try stops(of: sam).first)
        #expect(samStop.placeNotes.isEmpty)
        let custom = try #require(monday.sortedStops.first { $0.isCustomStop })
        #expect(custom.placeNotes.isEmpty)
    }

    // Only a change is written: a stop whose notes are already in step isn't.
    @Test func followReportsANotesChangeOnlyWhenThereIsOne() throws {
        let stop = try #require(try stops(of: pat).first)
        pat.defaultStopNotes = "Gate 1234"
        #expect(ClientStops.follow(stop, pat))
        #expect(!ClientStops.follow(stop, pat))
    }

    // At launch or after iCloud: a stop that only lags on its notes catches
    // up, and that is saved.
    @Test func updateAllSavesWhenOnlyNotesChanged() throws {
        pat.defaultStopNotes = "Gate 1234"           // changed without update(for:)
        try context.save()
        ClientStops.updateAll(in: context)
        #expect(try stops(of: pat).allSatisfy { $0.placeNotes == "Gate 1234" })
        #expect(!context.hasChanges)                 // saved
    }

    // Rule 2: a stop's own note that is exactly the place's previous notes
    // was only ever the copy stops used to start with, and is cleared when
    // the place's notes change; any other note is the user's and is kept.
    @Test(arguments: [
        // own, old place notes, new place notes, own afterwards
        ("Gate 1234", "Gate 1234", "Gate 5678", ""),                      // a pure copy goes
        ("  Gate 1234\n", "Gate 1234", "Gate 5678", ""),                  // trimmed, still the copy
        ("Gate 1234", "Gate 1234", "", ""),                               // emptied place notes: the copy still goes
        ("Gate 1234, dog", "Gate 1234", "Gate 5678", "Gate 1234, dog"),   // edited: the user's
        ("gate 1234", "Gate 1234", "Gate 5678", "gate 1234"),             // any difference keeps it
        ("Gate 1234", "", "Gate 1234", "Gate 1234"),                      // a first follow clears nothing
        ("", "Gate 1234", "Gate 5678", ""),
        ("Blade", "Gate 1234", "Gate 5678", "Blade"),
    ])
    func ownNoteFollowingPlaceNotes(_ row: (String, String, String, String)) {
        #expect(ClientStops.ownNote(row.0, following: row.1, to: row.2) == row.3)
    }

    // Rule 2 through follow, as a stop made before this change meets it.
    @Test func anOldStopsCopyIsClearedWhenTheNotesChange() throws {
        let stop = try #require(try stops(of: pat).first)
        let other = try #require(try stops(of: pat).last { $0.id != stop.id })
        pat.defaultStopNotes = "Gate 1234"
        stop.stopNotes = "Gate 1234"                 // the copy it was made with
        other.stopNotes = "Gate 1234, ring first"    // the user's own words
        ClientStops.update(for: pat)                 // first follow
        #expect(stop.stopNotes == "Gate 1234")
        #expect(stop.shownOwnNotes.isEmpty)          // not shown twice
        pat.defaultStopNotes = "Gate 5678"
        ClientStops.update(for: pat)
        #expect(stop.placeNotes == "Gate 5678")
        #expect(stop.stopNotes.isEmpty)
        #expect(other.stopNotes == "Gate 1234, ring first")
        #expect(other.shownOwnNotes == "Gate 1234, ring first")
    }

    // Rule 1: the stop's own note isn't shown when it says what the place's
    // notes say.
    @Test func anOwnNoteRepeatingThePlacesIsntShown() {
        #expect(ClientStops.shownOwnNote("Gate 1234", placeNotes: "Gate 1234").isEmpty)
        #expect(ClientStops.shownOwnNote(" Gate 1234\n", placeNotes: "Gate 1234").isEmpty)
        #expect(ClientStops.shownOwnNote("Ring first", placeNotes: "Gate 1234") == "Ring first")
        #expect(ClientStops.shownOwnNote("Ring first", placeNotes: "") == "Ring first")
        #expect(ClientStops.shownOwnNote("", placeNotes: "Gate 1234").isEmpty)
    }

    // Duplicate Route: a stop's own note that only copies the place's notes
    // isn't carried to the copy (the place's notes come with the place); a
    // real one is, and a custom stop keeps its note.
    @Test func duplicateRouteCarriesOnlyARealOwnNote() throws {
        pat.defaultStopNotes = "Gate 1234"
        sam.defaultStopNotes = "Dog in yard"
        ClientStops.updateAll(in: context)
        let original = monday.sortedStops
        original[0].stopNotes = " Gate 1234\n"
        original[1].stopNotes = "Ring first"
        original[2].stopNotes = "Key under mat"
        let copy = ClientStops.duplicate(monday, clients: [pat, sam], in: context)
        try context.save()
        #expect(copy.name == "Monday (Copy)")
        let copied = copy.sortedStops
        #expect(copied.map(\.clientName) == ["Pat Doe", "Sam Roe", "Salt shed"])
        #expect(copied.map(\.stopNotes) == ["", "Ring first", "Key under mat"])
        #expect(copied.map(\.placeNotes) == ["Gate 1234", "Dog in yard", ""])
    }

    // An inactive client stays off the copy, as off every new route.
    @Test func duplicateRouteLeavesInactiveClientsOff() throws {
        sam.isActive = false
        let copy = ClientStops.duplicate(monday, clients: [pat, sam], in: context)
        #expect(copy.sortedStops.map(\.clientName) == ["Pat Doe", "Salt shed"])
    }

    // A client changed on another device arrives through iCloud: the stops
    // follow then, not only at the next launch. A route app stays open for
    // days.
    @Test func stopsFollowWhenICloudBringsChanges() async throws {
        let center = NotificationCenter()
        let observer = ClientStops.followRemoteChanges(of: container, center: center, after: .zero)
        defer { center.removeObserver(observer) }
        pat.phone = "555-0111"                    // changed without update(for:)
        try context.save()
        #expect(try stops(of: pat).allSatisfy { $0.clientPhone == "555-0100" })
        center.post(name: .NSPersistentStoreRemoteChange, object: nil)
        try await waitUntil { (try? stops(of: pat).allSatisfy { $0.clientPhone == "555-0111" }) == true }
        #expect(!context.hasChanges)             // saved
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        var tries = 0
        while !condition() && tries < 500 {          // Up to 5 s on a busy CI runner.
            tries += 1
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
