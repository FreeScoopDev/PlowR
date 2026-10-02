import Foundation
import SwiftData
import Testing
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
        #expect(TriggerChecks.contractPlaces(of: h.client.id.uuidString, on: now, contracts: [contract],
                                             calendar: calendar) == [h.client.id.uuidString, "north"])
        // Outside its dates: none.
        #expect(TriggerChecks.contractPlaces(of: h.client.id.uuidString, on: now.addingTimeInterval(90 * 86_400),
                                             contracts: [contract], calendar: calendar).isEmpty)
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
        let check = TriggerChecks.checkAtStop(stop, of: h.client, run: run, routeName: "Tuesday",
                                              arrivedAt: now.addingTimeInterval(-120), note: "  half an inch ",
                                              operatorID: "op", in: h.context, now: now, calendar: calendar)
        #expect(check.isFromStop)
        #expect(check.placeID == "north")
        #expect(check.runID == run.uuidString && check.stopID == stop.id.uuidString)
        #expect(check.day == calendar.startOfDay(for: now))
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
        #expect(lines[0] == "Checked at the property on a route at 10:00 AM: below the contract's snow trigger, not cleared")
        #expect(lines[1] == "Arrived 9:58 AM (GPS, within about 100 m)")
        #expect(lines.contains("Route: Tuesday"))
        let marked = ProofOfService.lines(of: try #require(checks.first), timeZone: zone, locale: english)
        #expect(marked[0].contains("by hand") && marked[0].contains("not a check at the property"))
    }

    @Test func aChecksPhotoIsCaptionedAsAPhotoNotBeforeOrAfter() {
        let photo = StopPhoto(operatorID: "op", clientID: "c", routeID: "", isBefore: true, imageData: Data())
        photo.checkID = UUID().uuidString
        photo.capturedAt = now
        photo.captureSourceRaw = CaptureSource.camera.rawValue
        let caption = ProofOfService.caption(of: photo, visitDay: now, timeZone: calendar.timeZone,
                                             locale: Locale(identifier: "en_US"), calendar: calendar)
        #expect(caption.hasPrefix("Photo, taken"))
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
