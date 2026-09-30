//
//  PropertyTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A client's additional properties, and the one rule (Place) for where work
/// is: the client's own address (their main property, with their ID), or one
/// of their properties. Stops, visits, the Service Log, pricing and targets
/// all follow it.
@MainActor
struct PropertyTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func property(_ h: Harness, _ label: String, address: String, sortOrder: Int = 0) -> Property {
        let property = Property(label: label, address: address, operatorID: "op")
        property.latitude = 42.1
        property.longitude = -71.2
        property.sortOrder = sortOrder
        h.context.insert(property)
        property.client = h.client
        return property
    }

    // MARK: - Place

    @Test func theMainPlaceIsTheClientsOwnAddress() throws {
        let h = try Harness(stopCount: 1)
        h.client.goalMinutes = 20
        let main = try #require(Place.of(h.client, propertyID: ""))
        #expect(main.isMain)
        #expect(main.id == h.client.id.uuidString)
        #expect(main.address == h.client.address)
        #expect(main.goalMinutes == 20)
        #expect(Place.of(h.client, propertyID: h.client.id.uuidString) == main)
        #expect(Place.id(of: h.client, propertyID: "") == h.client.id.uuidString)
    }

    // A property removed, or not synced here yet, is missing: never the main one.
    @Test func aMissingPlaceIsNeverTheMainOne() throws {
        let h = try Harness(stopCount: 1)
        let gone = UUID().uuidString
        #expect(Place.of(h.client, propertyID: gone) == nil)
        #expect(Place.id(of: h.client, propertyID: gone) == gone)

        let stop = try #require(h.route.sortedStops.first)
        stop.propertyID = gone
        stop.clientAddress = "9 Elm St"
        ClientStops.follow(stop, h.client)
        #expect(stop.clientAddress == "9 Elm St")                                 // keeps its own
        StopServices.apply(["mow"], to: stop, client: h.client, allRoutes: true, in: h.context)
        #expect(h.client.expectedServiceIDs.isEmpty)                              // not the main house's
        #expect(Client.routeStops(for: [visit(h, at: gone)], from: [h.client], operatorID: "op").stops.isEmpty)
    }

    private func visit(_ h: Harness, at propertyID: String, on date: Date? = nil) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: "9 Elm St", scheduledDate: date ?? h.clock)
        visit.propertyID = propertyID
        h.context.insert(visit)
        return visit
    }

    @Test func aPropertyIsItsOwnPlace() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        rental.goalMinutes = 35
        rental.expectedServiceIDs = ["mow"]
        let place = try #require(Place.of(h.client, propertyID: rental.id.uuidString))
        #expect(!place.isMain)
        #expect(place.label == "Rental")
        #expect(place.address == "9 Elm St")
        #expect(place.goalMinutes == 35)
        #expect(place.expectedServiceIDs == ["mow"])
        #expect(place.zones.isEmpty)
    }

    @Test func allPlacesAreTheMainOneThenActivePropertiesInOrder() throws {
        let h = try Harness(stopCount: 1)
        let second = property(h, "B", address: "2 B St", sortOrder: 1)
        let first = property(h, "A", address: "1 A St", sortOrder: 0)
        let closed = property(h, "C", address: "3 C St", sortOrder: 2)
        closed.isActive = false
        #expect(Place.all(of: h.client).map(\.id) == [h.client.id.uuidString, first.id.uuidString, second.id.uuidString])
    }

    // MARK: - Following the place

    @Test func aStopFollowsItsPlacesAddress() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let atRental = RouteStop(order: 1, client: h.client, place: Place.of(rental))
        atRental.route = h.route
        h.context.insert(atRental)
        #expect(atRental.propertyID == rental.id.uuidString)
        #expect(atRental.clientAddress == "9 Elm St")

        rental.address = "11 Elm St"
        rental.latitude = 43
        h.client.address = "5 Main St"
        ClientStops.update(for: h.client)
        #expect(atRental.clientAddress == "11 Elm St")
        #expect(atRental.latitude == 43)
        #expect(h.route.sortedStops.first?.clientAddress == "5 Main St")          // the main stop follows the client
    }

    @Test func aVisitFollowsItsPlacesAddressAndItsSeriesStaysThere() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: "old", scheduledDate: Date().addingTimeInterval(86_400))
        visit.propertyID = rental.id.uuidString
        h.context.insert(visit)
        #expect(ClientVisits.follow(visit, h.client))
        #expect(visit.clientAddress == "9 Elm St")
        #expect(visit.makeContinuation(on: Date()).propertyID == rental.id.uuidString)
    }

    // MARK: - The Service Log, services and targets

    // A stop at a property: its job is at that property, and it isn't priced
    // by the main house's measurements (zones are the main one's for now), so
    // a per-square-foot service is priced as for any unmeasured client.
    @Test func aJobAtAPropertyIsRecordedThere() throws {
        let h = try Harness(stopCount: 0)
        let zone = PropertyZone(label: "Drive")
        zone.areaSquareFeet = 1_000
        h.context.insert(zone)
        zone.client = h.client
        let salt = ServiceItem(name: "Salt", category: "c", unitType: "perSqFt", pricePerUnit: 0.05, operatorID: "op")
        h.context.insert(salt)
        let rental = property(h, "Rental", address: "9 Elm St")
        let stop = RouteStop(order: 0, client: h.client, place: Place.of(rental))
        stop.route = h.route
        h.context.insert(stop)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        stop.completedServiceIDs = [salt.id.uuidString]
        store.completeShownStop()
        let record = try #require(try h.context.fetch(FetchDescriptor<ServiceRecord>()).first)
        #expect(record.propertyID == rental.id.uuidString)
        #expect(record.propertyAddress == "9 Elm St")
        #expect(record.lines.map(\.price) == [0.05])
        #expect(ServiceLog.lines(for: [salt.id.uuidString], client: h.client, in: h.context).map(\.price) == [50])
    }

    // The day's visit at the rental isn't completed by the main house's stop,
    // nor is one at a missing place.
    @Test func aStopCompletesOnlyTheVisitAtItsPlace() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let atRental = visit(h, at: rental.id.uuidString)
        let atMissing = visit(h, at: UUID().uuidString)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(atRental.status == .scheduled)
        #expect(atMissing.status == .scheduled)
    }

    // …and the rental's stop completes the rental's visit.
    @Test func aStopAtAPropertyCompletesTheVisitThere() throws {
        let h = try Harness(stopCount: 0)
        let rental = property(h, "Rental", address: "9 Elm St")
        let stop = RouteStop(order: 0, client: h.client, place: Place.of(rental))
        stop.route = h.route
        h.context.insert(stop)
        let atMain = visit(h, at: "")
        let atRental = visit(h, at: rental.id.uuidString)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(atRental.status == .completed)
        #expect(atMain.status == .scheduled)
    }

    @Test func aPropertysServicesAndTarget() throws {
        let h = try Harness(stopCount: 1)
        h.client.expectedServiceIDs = ["clear"]
        h.client.goalMinutes = 15
        let rental = property(h, "Rental", address: "9 Elm St")
        rental.expectedServiceIDs = ["mow"]
        rental.goalMinutes = 40
        let mainStop = try #require(h.route.sortedStops.first)
        let rentalStop = RouteStop(order: 1, client: h.client, place: Place.of(rental))
        rentalStop.route = h.route
        h.context.insert(rentalStop)
        try h.context.save()
        #expect(StopServices.expected(for: rentalStop, client: h.client) == ["mow"])
        #expect(RouteFacts.targetMinutes(of: rentalStop, client: h.client) == 40)
        #expect(RouteFacts.targetMinutes(of: mainStop, client: h.client) == 15)

        // "All routes" at the rental changes the rental's usual services and
        // its stops only.
        StopServices.setForThisRoute(["salt"], on: mainStop)
        StopServices.apply(["mow", "edge"], to: rentalStop, client: h.client, allRoutes: true, in: h.context)
        #expect(rental.expectedServiceIDs == ["mow", "edge"])
        #expect(h.client.expectedServiceIDs == ["clear"])
        #expect(mainStop.hasOwnServices)
    }

    // MARK: - Routes from the Schedule, removal, deletion

    @Test func aRouteFromTheScheduleGoesWhereEachVisitWasBooked() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let atMain = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: "", clientAddress: "",
                                    scheduledDate: h.clock)
        let atRental = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: "",
                                      clientAddress: "", scheduledDate: h.clock)
        atRental.propertyID = rental.id.uuidString
        let stops = Client.routeStops(for: [atMain, atRental], from: [h.client], operatorID: "op").stops
        #expect(stops.map(\.place.isMain) == [true, false])
        #expect(stops.last?.place.address == "9 Elm St")
    }

    // A visit moved to another client is at their main address, and removing
    // the first client's property never touches it.
    @Test func aVisitMovedToAnotherClientLeavesTheProperty() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let other = Client(name: "Bo", phone: "", address: "7 Oak St", operatorID: "op")
        h.context.insert(other)
        let moved = visit(h, at: rental.id.uuidString, on: h.clock.addingTimeInterval(86_400))
        let copy = visit(h, at: rental.id.uuidString, on: h.clock.addingTimeInterval(86_400))
        copy.clientID = other.id.uuidString                                       // as a synced older edit would leave it
        ClientVisits.book(moved, for: other, at: moved.propertyID)
        #expect(moved.propertyID.isEmpty)
        #expect(moved.clientAddress == "7 Oak St")
        try h.context.save()
        PropertyRemoval.remove(rental, in: h.context, now: h.clock)
        #expect(copy.modelContext != nil && !copy.isDeleted)
    }

    // Removed at 10:00: the rental's visit at 8:00 not done yet goes too (it
    // would have nowhere to be); the one done at 8:00 stays as history.
    @Test func removingAPropertyTakesTodaysUnfinishedVisits() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let today = Calendar.current.startOfDay(for: h.clock)
        let unfinished = visit(h, at: rental.id.uuidString, on: today.addingTimeInterval(8 * 3_600))
        let done = visit(h, at: rental.id.uuidString, on: today.addingTimeInterval(8 * 3_600))
        done.status = .completed
        try h.context.save()
        PropertyRemoval.remove(rental, in: h.context, now: today.addingTimeInterval(10 * 3_600))
        #expect(unfinished.isDeleted || unfinished.modelContext == nil)
        #expect(!done.isDeleted && done.modelContext != nil)
    }

    @Test func removingAPropertyTakesItsStopsAndVisitsAheadOnly() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let stop = RouteStop(order: 1, client: h.client, place: Place.of(rental))
        stop.route = h.route
        h.context.insert(stop)
        func visit(days: Double) -> ScheduledVisit {
            let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: "",
                                       clientAddress: "", scheduledDate: Date().addingTimeInterval(days * 86_400))
            visit.propertyID = rental.id.uuidString
            h.context.insert(visit)
            return visit
        }
        let ahead = visit(days: 2)
        let past = visit(days: -2)
        try h.context.save()
        #expect(PropertyRemoval.footprint(of: rental, in: h.context) == (1, 1))
        PropertyRemoval.remove(rental, in: h.context)
        #expect(stop.isDeleted || stop.modelContext == nil)
        #expect(ahead.isDeleted || ahead.modelContext == nil)
        #expect(!past.isDeleted && past.modelContext != nil)
        #expect(h.route.sortedStops.count == 1)
    }

    @Test func deletingAClientDeletesTheirProperties() throws {
        let h = try Harness(stopCount: 1)
        _ = property(h, "Rental", address: "9 Elm St")
        try h.context.save()
        ClientRemoval.delete(h.client, keepingRecords: false, in: h.context)
        #expect(try h.context.fetch(FetchDescriptor<Property>()).isEmpty)
    }

    // MARK: - Screens' rules

    @Test func aNewPropertyGoesLastAndEditingOneMovesItsStops() throws {
        let h = try Harness(stopCount: 1)
        let first = property(h, "A", address: "1 A St", sortOrder: 4)
        var draft = PropertyEditing.Draft()
        draft.label = "  Rental  "
        draft.address = "9 Elm St"
        draft.expectedServiceIDs = ["mow", "edge"]
        let rental = PropertyEditing.save(draft, to: nil, of: h.client, in: h.context)
        #expect(rental.client?.id == h.client.id)
        #expect(rental.sortOrder == 5)
        #expect(rental.label == "Rental")
        #expect(rental.expectedServiceIDs == ["edge", "mow"])
        #expect(Place.all(of: h.client).map(\.id).suffix(2) == [first.id.uuidString, rental.id.uuidString])

        let stop = RouteStop(order: 1, client: h.client, place: Place.of(rental))
        stop.route = h.route
        h.context.insert(stop)
        var moved = PropertyEditing.Draft(rental)
        moved.address = "11 Elm St"
        moved.latitude = 43
        PropertyEditing.save(moved, to: rental, of: h.client, in: h.context)
        #expect(stop.clientAddress == "11 Elm St")
        #expect(stop.latitude == 43)
        #expect(!PropertyEditing.Draft().canSave)
    }

    // A place made inactive is still shown where something is booked there.
    @Test func aPickerKeepsTheInactivePlaceItsVisitIsAt() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        rental.isActive = false
        #expect(Place.choices(of: h.client, keeping: "").count == 1)
        #expect(Place.choices(of: h.client, keeping: rental.id.uuidString).map(\.id).last == rental.id.uuidString)
        #expect(Place.of(rental).title(for: "Pat") == "Pat · Rental")
    }

    // The client picker tells a client's places apart, and the main one's key
    // is the same whether its stop keeps "" or the client's ID.
    @Test func eachPlaceHasItsOwnPickerKey() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let main = try #require(h.route.sortedStops.first)
        let atRental = RouteStop(order: 1, client: h.client, place: Place.of(rental))
        #expect(main.placeKey != atRental.placeKey)
        #expect(main.placeKey == Place.key(clientID: h.client.id, propertyID: h.client.id.uuidString))
        #expect(atRental.placeKey == Place.key(clientID: h.client.id, propertyID: Place.of(rental).storedID))
    }

    // Booking a visit at one of the client's places, and one that isn't theirs.
    @Test func aVisitIsBookedAtTheChosenPlace() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        let booked = visit(h, at: "")
        ClientVisits.book(booked, for: h.client, at: rental.id.uuidString)
        #expect(booked.propertyID == rental.id.uuidString)
        #expect(booked.clientAddress == "9 Elm St")
        ClientVisits.book(booked, for: h.client, at: UUID().uuidString)          // not theirs
        #expect(booked.propertyID.isEmpty)
        #expect(booked.clientAddress == h.client.address)

        // Its own place, not synced here yet, is kept as it is.
        let unsynced = UUID().uuidString
        let waiting = visit(h, at: unsynced)
        ClientVisits.book(waiting, for: h.client, at: unsynced)
        #expect(waiting.propertyID == unsynced)
        #expect(waiting.clientAddress == "9 Elm St")
    }

    @Test func removingSaysWhatGoesWithIt() {
        #expect(PropertyEditing.removalMessage(stops: 1, visits: 3).hasPrefix("This also removes 1 route stop and 3 visits"))
        #expect(PropertyEditing.removalMessage(stops: 0, visits: 0)
                == "Work already done there stays in the client's Service History.")
        #expect(PropertyEditing.removalMessage(stops: 2, visits: 1)
                == "This also removes 2 route stops and 1 visit not done yet. "
                + "Work already done there stays in the client's Service History.")
    }

    // A new visit booked from the Schedule: blank until a client is picked,
    // then their own address's notes and time, then the property's, until
    // typed over.
    @Test func aNewVisitsNotesFollowThePlaceUntilTypedOver() {
        var notes = ""
        var fill = PlaceFill("")
        fill.follow(&notes, to: "Dog in yard")                                    // the client picked
        #expect(notes == "Dog in yard")
        fill.follow(&notes, to: "Key under mat")                                  // the rental picked
        #expect(notes == "Key under mat")
        notes = "Ring first"                                                      // typed over
        fill.follow(&notes, to: "Dog in yard")
        #expect(notes == "Ring first")
    }

    @Test func workLoggedAtAPropertyIsRecordedThere() throws {
        let h = try Harness(stopCount: 0)
        let rental = property(h, "Rental", address: "9 Elm St")
        let record = ServiceLog.logWork(StopRecording(services: [], zones: []), notes: "n", performedAt: h.clock,
                                        minutes: 0, for: h.client, at: rental.id.uuidString, operatorID: "op",
                                        in: h.context)
        #expect(record.propertyID == rental.id.uuidString)
        #expect(record.propertyAddress == "9 Elm St")
        let atHome = ServiceLog.logWork(StopRecording(services: [], zones: []), notes: "n", performedAt: h.clock,
                                        minutes: 0, for: h.client, operatorID: "op", in: h.context)
        #expect(atHome.propertyID == h.client.id.uuidString)
        #expect(atHome.propertyAddress == h.client.address)
    }

    // Every screen that makes a stop at a place starts it with the place's notes.
    @Test func aNewStopStartsWithItsPlacesNotes() throws {
        let h = try Harness(stopCount: 1)
        let rental = property(h, "Rental", address: "9 Elm St")
        rental.stopNotes = "Key under mat"
        #expect(RouteStop(order: 0, client: h.client, place: Place.of(rental)).stopNotes == "Key under mat")
    }
}
