//
//  ProofOfServiceTests.swift
//  PlowRTests
//

import Foundation
import PDFKit
import SwiftData
import Testing
import UIKit
@testable import PlowR

/// Proof of service: the visits at a place over a period, with their times,
/// services, notes and photos.
@MainActor
struct ProofOfServiceTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .distantPast
    }

    @discardableResult
    private func job(_ h: Harness, started: Date?, finished: Date, propertyID: String? = nil,
                     services: [String] = ["Plowing"], notes: String = "", source: ServiceRecordSource = .route,
                     key: String? = nil) -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: key ?? "stop:\(UUID().uuidString)", source: source)
        record.clientID = h.client.id.uuidString
        record.propertyID = propertyID ?? h.client.id.uuidString
        record.startedAt = started
        record.performedAt = finished
        record.minutes = started.map { finished.timeIntervalSince($0) / 60 } ?? 0
        record.lines = services.map { .init(serviceID: $0, name: $0, unitType: "flat", price: 50) }
        record.notes = notes
        record.routeName = "Tuesday"
        h.context.insert(record)
        return record
    }

    /// A photo of noise, so its size depends on its resolution as a real one's does.
    private func photo(_ h: Harness, for record: ServiceRecord, before: Bool, at time: Date, pixels: CGFloat = 40) -> StopPhoto {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var generator = SystemRandomNumberGenerator()
        let image = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { context in
            for y in stride(from: 0, to: Int(pixels), by: 4) {
                for x in stride(from: 0, to: Int(pixels), by: 4) {
                    UIColor(white: CGFloat(Int.random(in: 0...255, using: &generator)) / 255, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }
        let photo = StopPhoto(operatorID: "op", clientID: h.client.id.uuidString, routeID: "", isBefore: before,
                              imageData: image.jpegData(compressionQuality: 0.9) ?? Data())
        photo.recordID = record.id.uuidString
        photo.takenAt = time
        h.context.insert(photo)
        return photo
    }

    @Test func itsVisitsAreAtThePlaceInThePeriodOldestFirst() throws {
        let h = try Harness(stopCount: 0)
        let rental = Property(label: "Rental", address: "9 Elm St", operatorID: "op")
        h.context.insert(rental)
        rental.client = h.client
        let second = job(h, started: date(2027, 1, 20, 5), finished: date(2027, 1, 20, 5, 30))
        // A night route: started on the 14th, finished after midnight. It's the 14th's work.
        let first = job(h, started: date(2027, 1, 14, 23, 40), finished: date(2027, 1, 15, 0, 15))
        job(h, started: date(2027, 1, 16, 5), finished: date(2027, 1, 16, 6), propertyID: rental.id.uuidString)
        job(h, started: date(2026, 12, 31, 5), finished: date(2026, 12, 31, 6))                  // before the period
        let visits = ProofOfService.visits(of: h.client, placeID: h.client.id.uuidString,
                                           from: date(2027, 1, 1), to: date(2027, 1, 31), in: h.context,
                                           calendar: calendar)
        #expect(visits.map(\.record.id) == [first.id, second.id])
        // By the day it started: on the 15th, the night route isn't there.
        #expect(ProofOfService.visits(of: h.client, placeID: h.client.id.uuidString, from: date(2027, 1, 15),
                                      to: date(2027, 1, 15), in: h.context, calendar: calendar).isEmpty)
        #expect(ProofOfService.visits(of: h.client, placeID: rental.id.uuidString, from: date(2027, 1, 1),
                                      to: date(2027, 1, 31), in: h.context, calendar: calendar).count == 1)
        #expect(ProofOfService.visits(of: h.client, placeID: h.client.id.uuidString, from: date(2027, 1, 20, 12),
                                      to: date(2027, 1, 20, 12), in: h.context, calendar: calendar).count == 1)
    }

    // The same job recorded on two devices before the merge is listed once.
    @Test func aJobRecordedTwiceIsListedOnce() throws {
        let h = try Harness(stopCount: 0)
        let older = job(h, started: date(2027, 1, 14, 5), finished: date(2027, 1, 14, 5, 30), key: "stop:a:b")
        older.createdAt = date(2027, 1, 14, 5, 30)
        let newer = job(h, started: date(2027, 1, 14, 5), finished: date(2027, 1, 14, 5, 31), key: "stop:a:b")
        newer.createdAt = date(2027, 1, 14, 5, 31)
        let visits = ProofOfService.visits(of: h.client, placeID: h.client.id.uuidString,
                                           from: date(2027, 1, 14), to: date(2027, 1, 14), in: h.context, calendar: calendar)
        #expect(visits.map(\.record.id) == [older.id])
    }

    // Saved together, photos share a time: before comes first by its kind.
    @Test func eachVisitHasItsPhotosBeforeThenAfter() throws {
        let h = try Harness(stopCount: 0)
        let record = job(h, started: date(2027, 1, 14, 5), finished: date(2027, 1, 14, 5, 28))
        let saved = date(2027, 1, 14, 5, 29)
        let after = photo(h, for: record, before: false, at: saved)
        let before = photo(h, for: record, before: true, at: saved)
        _ = photo(h, for: job(h, started: nil, finished: date(2027, 1, 15, 5), source: .manual), before: true,
                  at: date(2027, 1, 15, 5))
        let visits = ProofOfService.visits(of: h.client, placeID: h.client.id.uuidString,
                                           from: date(2027, 1, 14), to: date(2027, 1, 14), in: h.context, calendar: calendar)
        #expect(visits.first?.photos.map(\.id) == [before.id, after.id])
    }

    // Times only where PlowR recorded them, said for what they are.
    @Test func onlyRecordedTimesArePrintedForWhatTheyAre() throws {
        let h = try Harness(stopCount: 0)
        let zone = TimeZone(identifier: "America/New_York") ?? .current
        let english = Locale(identifier: "en_US")
        func lines(_ record: ServiceRecord, address: String = "0 Main St") -> [String] {
            // iOS puts a narrow no-break space before AM and PM.
            ProofOfService.lines(of: ProofOfService.Visit(record: record, photos: []), placeAddress: address,
                                 timeZone: zone, locale: english).map { $0.replacingOccurrences(of: "\u{202F}", with: " ") }
        }
        let route = job(h, started: date(2027, 1, 14, 4, 52), finished: date(2027, 1, 14, 5, 20), notes: "Salted the steps")
        route.propertyAddress = "0 Main St"
        #expect(lines(route)[0] == "Started 4:52 AM · Completed 5:20 AM · 28 min, including travel")
        #expect(lines(route)[1] == "Tracked on a route")
        #expect(lines(route).contains("Notes: Salted the steps") && lines(route).contains("Route: Tuesday"))
        // Booked for 7:00, ticked off later: no time is printed, least of all 7:00.
        let fromSchedule = job(h, started: nil, finished: date(2027, 1, 15, 7), source: .visit)
        #expect(lines(fromSchedule)[0] == "Time not recorded by PlowR")
        #expect(!lines(fromSchedule).joined().contains("7:00"))
        #expect(lines(fromSchedule)[1] == "Completed from the Schedule")
        let byHand = job(h, started: nil, finished: date(2027, 1, 16, 9), services: [], source: .manual)
        #expect(lines(byHand)[1] == "Logged by hand")
        #expect(lines(byHand).contains("No services recorded"))
        // Recorded at an address since changed: the one the work was at.
        route.propertyAddress = "1 Old Rd"
        #expect(lines(route, address: "2 New Rd").contains("At 1 Old Rd"))
        #expect(!ProofOfService.note(timeZone: zone).contains("on site"))
    }

    @Test func thePeriodsAreBegunContractsThenRecentAndThisYear() throws {
        let h = try Harness(stopCount: 0)
        func contract(_ name: String, _ start: Date, _ end: Date, signed: Bool = true) -> Contract {
            let contract = Contract(name: name, startDate: start, endDate: end, operatorID: "op")
            contract.placeIDs = [h.client.id.uuidString]
            if signed { contract.signedAt = date(2026, 10, 1) }
            h.context.insert(contract)
            contract.client = h.client
            return contract
        }
        _ = contract("Winter", date(2026, 11, 1), date(2027, 3, 31))
        _ = contract("Next Winter", date(2027, 11, 1), date(2028, 3, 31))       // not begun
        _ = contract("Draft", date(2026, 11, 1), date(2027, 3, 31), signed: false)
        let ended = contract("Lawn", date(2026, 4, 1), date(2026, 10, 31))
        ended.cancelledAt = date(2026, 7, 15)
        let periods = ProofOfService.periods(for: h.client, placeID: h.client.id.uuidString, now: date(2027, 2, 1),
                                             calendar: calendar)
        #expect(periods.map(\.label) == ["Winter", "Lawn", "Last 30 Days", "This Year"])
        #expect(periods[0].end == date(2027, 2, 1))                               // not past today
        #expect(periods[1].end == date(2026, 7, 15))                              // to the day it was cancelled
        #expect(periods.allSatisfy { $0.start <= $0.end })
    }

    // An inactive or removed property can still be reported on.
    @Test func everyPlaceWithWorkIsOffered() throws {
        let h = try Harness(stopCount: 0)
        let rental = Property(label: "Rental", address: "9 Elm St", operatorID: "op")
        rental.isActive = false
        h.context.insert(rental)
        rental.client = h.client
        let gone = job(h, started: nil, finished: date(2027, 1, 5), propertyID: UUID().uuidString, source: .manual)
        gone.propertyAddress = "4 Gone Ln"
        let places = ProofOfService.places(of: h.client, in: h.context)
        #expect(places.map(\.id) == [h.client.id.uuidString, rental.id.uuidString, gone.propertyID])
        #expect(places[1].label == "Rental (inactive)")
        #expect(places[2].address == "4 Gone Ln")
    }

    // The report: every visit, nothing overstated, and real-size photos shrunk.
    @Test func theReportHasEveryVisitAndStaysSmall() throws {
        let h = try Harness(stopCount: 0)
        for day in 1...12 {
            let record = job(h, started: date(2027, 1, day, 5), finished: date(2027, 1, day, 5, 30), notes: "Visit \(day).")
            _ = photo(h, for: record, before: true, at: date(2027, 1, day, 5, 31), pixels: 1_600)
        }
        let visits = ProofOfService.visits(of: h.client, placeID: h.client.id.uuidString,
                                           from: date(2027, 1, 1), to: date(2027, 1, 31), in: h.context, calendar: calendar)
        let period = ProofOfService.Period(label: "January", start: date(2027, 1, 1), end: date(2027, 1, 31))
        let place = ProofOfService.ReportPlace(id: h.client.id.uuidString, label: "Main Address", address: h.client.address)
        let data = ProofOfService.pdf(client: h.client, place: place, period: period, visits: visits, profile: nil)
        let document = try #require(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        #expect(text.contains("SERVICE REPORT") && !text.contains("PROOF OF SERVICE"))
        #expect(text.contains("12 visits recorded"))
        #expect((1...12).allSatisfy { text.contains("Visit \($0).") })
        #expect(!text.contains("on site"))
        #expect(text.contains("About this report"))
        let originals = visits.flatMap(\.photos).reduce(0) { $0 + $1.imageData.count }
        #expect(data.count < originals / 4)                                       // shrunk, not the originals
        #expect(ProofOfService.fileName(client: h.client, period: period) == "Service Report - \(h.client.name) - January.pdf")
    }
}
