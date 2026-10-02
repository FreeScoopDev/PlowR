import Foundation
import SwiftData
import Testing
import UIKit
@testable import PlowR

/// Below the contract's snow trigger: the forecast said a storm, but less
/// fell at a client's place. Marked by hand or checked at the stop; the
/// storm card, the route page, the route and the Service Report follow it.
@MainActor
struct BelowTriggerTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: 12, hour: 9)) ?? .distantPast
    }

    private func snowContract(_ h: Harness, for client: Client, trigger: Double = 2) -> Contract {
        let contract = Contract(name: "Season", startDate: now.addingTimeInterval(-30 * 86_400),
                                endDate: now.addingTimeInterval(60 * 86_400), operatorID: "op")
        contract.clientID = client.id.uuidString
        contract.clientName = client.name
        contract.placeIDs = [client.id.uuidString]
        contract.triggerInches = trigger
        contract.signedAt = contract.startDate
        h.context.insert(contract)
        return contract
    }

    // MARK: - Marking

    @Test func markingIsPerPlaceAndDayOnceAndUnmarkingRemovesEveryCopy() throws {
        let h = try Harness(stopCount: 1)
        let id = h.client.id.uuidString
        TriggerChecks.mark(clientID: id, clientName: "Pat", places: [id, "north"], on: now, operatorID: "op",
                           in: h.context, now: now, calendar: calendar)
        TriggerChecks.mark(clientID: id, clientName: "Pat", places: [id], on: now.addingTimeInterval(3_600),
                           operatorID: "op", in: h.context, now: now, calendar: calendar)
        var all = try h.context.fetch(FetchDescriptor<TriggerCheck>())
        #expect(all.count == 2)                                 // the same place and day isn't marked twice
        #expect(TriggerChecks.isMarked(id, placeID: "north", on: now, in: all, calendar: calendar))
        #expect(!TriggerChecks.isMarked(id, on: now.addingTimeInterval(86_400), in: all, calendar: calendar))
        // Another device's copy, before iCloud brought this one's.
        let copy = TriggerCheck(operatorID: "op", clientID: id, clientName: "Pat", placeID: id,
                                day: calendar.startOfDay(for: now))
        h.context.insert(copy)
        TriggerChecks.unmark(id, places: [id], on: now, in: h.context, calendar: calendar)
        all = try h.context.fetch(FetchDescriptor<TriggerCheck>())
        #expect(all.map(\.placeID) == ["north"])
    }

    @Test func aMarkOnTheStormCardCoversTheirContractedPlacesThatDay() throws {
        let h = try Harness(stopCount: 1)
        let contract = snowContract(h, for: h.client)
        contract.placeIDs = [h.client.id.uuidString, "north"]
        #expect(TriggerChecks.contractPlaces(of: h.client.id.uuidString, on: now, contracts: [contract], services: [],
                                             calendar: calendar) == [h.client.id.uuidString, "north"])
        // Outside its dates: none.
        #expect(TriggerChecks.contractPlaces(of: h.client.id.uuidString, on: now.addingTimeInterval(90 * 86_400),
                                             contracts: [contract], services: [], calendar: calendar).isEmpty)
        // Not a snow contract (no trigger, no snow service): none.
        contract.triggerInches = 0
        #expect(TriggerChecks.contractPlaces(of: h.client.id.uuidString, on: now, contracts: [contract], services: [],
                                             calendar: calendar).isEmpty)
    }

    @Test func aClientIsMarkedOnlyWhenEveryContractedPlaceIs() throws {
        let h = try Harness(stopCount: 1)
        let id = h.client.id.uuidString
        let contract = snowContract(h, for: h.client)
        contract.placeIDs = [id, "north"]
        var checks = TriggerChecks.mark(clientID: id, clientName: "Pat", places: [id], on: now, operatorID: "op",
                                        in: h.context, now: now, calendar: calendar)
        #expect(!TriggerChecks.isClientMarked(id, on: now, contracts: [contract], services: [], in: checks,
                                              calendar: calendar))
        checks += TriggerChecks.mark(clientID: id, clientName: "Pat", places: ["north"], on: now, operatorID: "op",
                                     in: h.context, now: now, calendar: calendar)
        #expect(TriggerChecks.isClientMarked(id, on: now, contracts: [contract], services: [], in: checks,
                                             calendar: calendar))
        // Another day's marks don't count.
        #expect(!TriggerChecks.isClientMarked(id, on: now.addingTimeInterval(86_400), contracts: [contract],
                                              services: [], in: checks, calendar: calendar))
    }

    // MARK: - The storm card

    @Test func aMarkedClientIsNeitherReachedNorNotButStillSetsTheStorm() throws {
        let h = try Harness(stopCount: 2)
        let marked = snowContract(h, for: h.clients[0], trigger: 1)
        let open = snowContract(h, for: h.clients[1], trigger: 1)
        let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let check = TriggerCheck(operatorID: "op", clientID: marked.clientID, clientName: "", placeID: marked.clientID,
                                 day: day)
        h.context.insert(check)
        let forecast = DayForecast(date: day, maxTempF: 30, minTempF: 20, weatherCode: 73, precipitationMm: 5,
                                   snowfallInches: 3)
        let book = StormWatch.Book(contracts: [marked, open], services: [],
                                   activeClientIDs: [marked.clientID, open.clientID], operatorID: "op",
                                   checks: [check])
        let storm = try #require(StormWatch.storm(in: [forecast], book: book, now: now, calendar: calendar))
        #expect(storm.met.map(\.clientID) == [open.clientID])
        #expect(storm.markedBelow.map(\.clientID) == [marked.clientID])
        // Everyone marked: the card stays, so a mark can be taken off.
        let alone = StormWatch.Book(contracts: [marked], services: [], activeClientIDs: [marked.clientID],
                                    operatorID: "op", checks: [check])
        let still = try #require(StormWatch.storm(in: [forecast], book: alone, now: now, calendar: calendar))
        #expect(still.met.isEmpty && still.markedBelow.count == 1)
    }

    // MARK: - The route page

    @Test func aStopBelowTriggerStartsSkippedAndCanBeIncludedAnyway() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        var run = TodaysRun(routeStops: [a, b, c], belowTrigger: [b])
        #expect(run.stops == [a, c])
        run.toggle(b)                                   // included anyway
        #expect(run.stops == [a, b, c])
        #expect(run.skippedByHand.isEmpty)
        run.toggle(b)
        #expect(run.stops == [a, c])
        run.toggle(a)                                   // by hand, as before
        #expect(run.stops == [c])
        #expect(run.skipping(from: 0) == [a, b])
    }

    @Test func includeTodayBringsBackAStopSkippedBothWays() {
        let a = UUID()
        var run = TodaysRun(routeStops: [a], skipped: [a], belowTrigger: [a])
        run.toggle(a)
        #expect(run.stops == [a])
        run.toggle(a)
        #expect(run.stops.isEmpty)
        #expect(run.skippedByHand.isEmpty)          // skipped again as below trigger, not by hand
    }

    // MARK: - At the stop

    @Test func passingAStopMovesOnWithoutCreditingAVisit() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        let first = h.route.sortedStops[0]
        h.clock += 600
        #expect(store.passCurrentStop(expecting: first.id) == .advanced(nextStopIndex: 1))
        #expect(store.currentStopID == h.route.sortedStops[1].id)
        #expect(first.actualMinutes == 0)                       // the recap shows it not serviced
        #expect(h.clients[0].totalVisits == 0)
        #expect(try h.context.fetch(FetchDescriptor<ServiceRecord>()).isEmpty)
        // The stop on screen only.
        #expect(store.passCurrentStop(expecting: first.id) == .stopChanged)
        // The last stop finishes the route.
        #expect(store.passCurrentStop(expecting: h.route.sortedStops[1].id) == .finishedLastStop)
        #expect(store.allStopsDone)
    }

    @Test func aCheckAtTheStopKeepsTheRunTheArrivalAndThePlace() throws {
        let h = try Harness(stopCount: 1)
        let stop = h.route.sortedStops[0]
        stop.propertyID = "north"
        let run = UUID()
        // Saved at 1 AM on a storm route started the evening before: the storm day's.
        let started = now.addingTimeInterval(-10 * 3_600)
        let check = TriggerChecks.checkAtStop(stop, of: h.client, run: run, routeName: "Tuesday",
                                              arrivedAt: now.addingTimeInterval(-120), day: started,
                                              note: "  half an inch ", operatorID: "op", in: h.context, now: now,
                                              calendar: calendar)
        #expect(check.isFromStop)
        #expect(check.placeID == "north")
        #expect(check.runID == run.uuidString && check.stopID == stop.id.uuidString)
        #expect(check.day == calendar.startOfDay(for: started))
        #expect(check.checkedAt == now)
        #expect(check.note == "half an inch")
    }

    // MARK: - The Service Report

    @Test func theReportListsOneCheckADayAndSaysWhichKind() throws {
        let h = try Harness(stopCount: 1)
        let id = h.client.id.uuidString
        let english = Locale(identifier: "en_US")
        let zone = calendar.timeZone
        func make(_ fromStop: Bool, at time: Date, place: String = "") -> TriggerCheck {
            let check = TriggerCheck(operatorID: "op", clientID: id, clientName: "Pat", placeID: place.isEmpty ? id : place,
                                     day: calendar.startOfDay(for: time))
            check.checkedAt = time
            if fromStop {
                check.sourceRaw = "stop"
                check.routeName = "Tuesday"
                check.arrivedAt = time.addingTimeInterval(-120)
            }
            h.context.insert(check)
            return check
        }
        _ = make(false, at: now)                                         // marked first, by hand
        let atStop = make(true, at: now.addingTimeInterval(3_600))       // then checked there
        _ = make(false, at: now.addingTimeInterval(-86_400))
        _ = make(true, at: now, place: "elsewhere")
        let checks = ProofOfService.checks(of: h.client, placeID: id, from: now.addingTimeInterval(-7 * 86_400),
                                           to: now, in: h.context, calendar: calendar)
        #expect(checks.count == 2)
        #expect(checks.last?.check.id == atStop.id)                      // the stop's check speaks for the day
        let lines = ProofOfService.lines(of: try #require(checks.last), timeZone: zone, locale: english)
            .map { $0.replacingOccurrences(of: "\u{202F}", with: " ") }
        #expect(lines[0] == "Checked on a route at 10:00 AM: below the contract's snow trigger, not cleared")
        #expect(lines[1] == "Arrived 9:58 AM (GPS, within about 100 m)")
        #expect(lines.contains("Route: Tuesday"))
        atStop.arrivedAt = nil
        let uncaught = ProofOfService.lines(of: ProofOfService.Check(check: atStop, photos: []), timeZone: zone,
                                            locale: english)
        #expect(uncaught[1] == "Arrival not caught (GPS)")
        let marked = ProofOfService.lines(of: try #require(checks.first), timeZone: zone, locale: english)
        #expect(marked[0].contains("by hand") && marked[0].contains("not a check at the property"))
        // The note speaks of snow triggers only on a report with such days.
        #expect(!ProofOfService.note(timeZone: zone).contains("snow"))
        #expect(ProofOfService.note(withChecks: true, timeZone: zone).contains("below the contract's snow trigger"))
    }

    @Test func unmarkingTakesOffMarksByHandButNotTheCrewsCheck() throws {
        let h = try Harness(stopCount: 1)
        let id = h.client.id.uuidString
        TriggerChecks.mark(clientID: id, clientName: "Pat", places: [id], on: now, operatorID: "op", in: h.context,
                           now: now, calendar: calendar)
        let stopCheck = TriggerChecks.checkAtStop(h.route.sortedStops[0], of: h.client, run: UUID(), routeName: "",
                                                  arrivedAt: nil, day: now, note: "", operatorID: "op",
                                                  in: h.context, now: now, calendar: calendar)
        let photo = StopPhoto(operatorID: "op", clientID: id, routeID: "", isBefore: true, imageData: Data([1]))
        photo.checkID = stopCheck.id.uuidString
        h.context.insert(photo)
        TriggerChecks.unmark(id, on: now, in: h.context, calendar: calendar)
        #expect(try h.context.fetch(FetchDescriptor<TriggerCheck>()).map(\.id) == [stopCheck.id])
        #expect(try h.context.fetch(FetchDescriptor<StopPhoto>()).count == 1)
        // Removed on purpose (the contract's page): its photos go with it.
        TriggerChecks.delete(stopCheck, in: h.context)
        #expect(try h.context.fetch(FetchDescriptor<StopPhoto>()).isEmpty)
    }

    // MARK: - Below Trigger, saved at the stop

    @Test func belowTriggerMovesOnAndKeepsTheCheckWithItsPhotos() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        h.clock += 600
        store.siteEntered(stops[0].id.uuidString, at: h.clock - 300)
        let photo = CapturedPhoto(image: UIImage(systemName: "circle") ?? UIImage(), capturedAt: h.clock, source: .camera)
        let outcome = TriggerChecks.passBelowTrigger(stops[0], of: h.clients[0], store: store, routeName: "Tuesday",
                                                     operatorID: "op", note: "Dusting", photos: [photo],
                                                     in: h.context, now: h.clock)
        #expect(outcome == .movedOn)
        #expect(store.currentStopID == stops[1].id)
        let check = try #require(try h.context.fetch(FetchDescriptor<TriggerCheck>()).first)
        #expect(check.arrivedAt == h.clock - 300)
        #expect(check.note == "Dusting")
        #expect(try h.context.fetch(FetchDescriptor<StopPhoto>()).first?.checkID == check.id.uuidString)
        #expect(try h.context.fetch(FetchDescriptor<ServiceRecord>()).isEmpty)
        // Again for the same stop (a double tap): nothing more.
        #expect(TriggerChecks.passBelowTrigger(stops[0], of: h.clients[0], store: store, routeName: "", operatorID: "op",
                                               note: "", photos: [], in: h.context) == .alreadyPast)
        #expect(try h.context.fetch(FetchDescriptor<TriggerCheck>()).count == 1)
        // The last stop finishes the route.
        #expect(TriggerChecks.passBelowTrigger(stops[1], of: h.clients[1], store: store, routeName: "", operatorID: "op",
                                               note: "", photos: [], in: h.context) == .finishedRoute)
    }

    @Test func aRouteChangedElsewhereKeepsTheCheckButDoesntMoveOn() throws {
        let h = try Harness(stopCount: 3)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        // Another device removed the first stop: the screen still showed it.
        let shown = stops[0]
        h.context.delete(stops[0])
        try h.context.save()
        let outcome = TriggerChecks.passBelowTrigger(shown, of: h.clients[0], store: store, routeName: "",
                                                     operatorID: "op", note: "", photos: [], in: h.context)
        #expect(outcome == .routeChanged)
        #expect(store.currentStopID == stops[1].id)            // not moved past the next client
        let check = try #require(try h.context.fetch(FetchDescriptor<TriggerCheck>()).first)
        #expect(check.clientID == h.clients[0].id.uuidString && check.arrivedAt == nil)
    }

    @Test func belowTriggerIsOfferedOnlyForSnowWorkAtAContractedPlace() throws {
        let h = try Harness(stopCount: 1)
        let stop = h.route.sortedStops[0]
        let snow = ServiceItem(name: "Clearing", category: ServiceCatalog.snowKey, unitType: "flat", pricePerUnit: 50,
                               operatorID: "op")
        let mowing = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 40, operatorID: "op")
        [snow, mowing].forEach { h.context.insert($0) }
        let contract = snowContract(h, for: h.client)
        func offered() -> Bool {
            TriggerChecks.trigger(for: stop, client: h.client, on: now, contracts: [contract],
                                  services: [snow, mowing]) != nil
        }
        #expect(offered())                                          // no services set: offered
        stop.hasOwnServices = true
        stop.expectedServiceIDs = [mowing.id.uuidString]
        #expect(!offered())                                         // a mowing stop
        stop.expectedServiceIDs = [snow.id.uuidString]
        #expect(offered())
        stop.propertyID = "elsewhere"                               // a place the contract doesn't cover
        #expect(!offered())
    }

    @Test func aChecksPhotoIsCaptionedBelowTriggerNotBeforeOrAfter() {
        let photo = StopPhoto(operatorID: "op", clientID: "c", routeID: "", isBefore: true, imageData: Data())
        photo.checkID = UUID().uuidString
        photo.capturedAt = now
        photo.captureSourceRaw = CaptureSource.camera.rawValue
        let caption = ProofOfService.caption(of: photo, visitDay: now, timeZone: calendar.timeZone,
                                             locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(caption.hasPrefix("Below Trigger, taken"))
        #expect(photo.kindLabel == "Below Trigger")
    }

    // MARK: - Deleting a client

    @Test func checksAreKeptOrDeletedWithTheRecords() throws {
        for keeping in [true, false] {
            let h = try Harness(stopCount: 1)
            TriggerChecks.mark(clientID: h.client.id.uuidString, clientName: "Pat", places: [h.client.id.uuidString],
                               on: now, operatorID: "op", in: h.context, now: now, calendar: calendar)
            ClientRemoval.delete(h.client, keepingRecords: keeping, in: h.context, now: now)
            #expect(try h.context.fetch(FetchDescriptor<TriggerCheck>()).count == (keeping ? 1 : 0))
        }
    }
}
