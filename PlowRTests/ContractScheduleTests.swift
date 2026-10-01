//
//  ContractScheduleTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The visits a contract books: its days, every so many weeks, at each of
/// its places, through its last day; booked again, replaced; cancelled or
/// ended early, taken off.
@MainActor
struct ContractScheduleTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? .distantPast
    }

    /// A signed mowing contract, Thursday Apr 1 – Thursday Apr 29 2027.
    private func mowing(_ h: Harness, weekdays: [Int] = [3], every weeks: Int = 1) -> Contract {
        let contract = Contract(name: "Mowing", startDate: date(2027, 4, 1), endDate: date(2027, 4, 29), operatorID: "op")
        contract.pricingRaw = Contracts.Pricing.perVisit.rawValue
        contract.price = 45
        contract.serviceIDs = ["mow"]
        contract.placeIDs = [h.client.id.uuidString]
        contract.clientID = h.client.id.uuidString
        contract.scheduleWeekdays = weekdays
        contract.scheduleIntervalWeeks = weeks
        h.context.insert(contract)
        contract.client = h.client
        contract.signedAt = date(2027, 3, 1)
        return contract
    }

    @Test func itsDaysInWords() throws {
        let h = try Harness(stopCount: 0)
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US")
        #expect(ContractSchedule.summary(of: mowing(h), calendar: english) == "Every Tuesday")
        #expect(ContractSchedule.summary(of: mowing(h, weekdays: [6, 3], every: 2), calendar: english)
                == "Every 2 weeks on Tuesday and Friday")
    }

    @Test func itsVisitsAreOnItsDaysThroughItsLastDay() throws {
        let h = try Harness(stopCount: 0)
        let tuesdays = ContractSchedule.dates(of: mowing(h), now: date(2027, 3, 20), calendar: calendar)
        #expect(tuesdays == [6, 13, 20, 27].map { date(2027, 4, $0, ContractSchedule.hour) })
        // Booked mid-season: from today on.
        #expect(ContractSchedule.dates(of: mowing(h), now: date(2027, 4, 14), calendar: calendar).count == 2)
        // Every 2 weeks keeps the weeks counted from its start.
        let fortnightly = ContractSchedule.dates(of: mowing(h, every: 2), now: date(2027, 4, 10), calendar: calendar)
        #expect(fortnightly == [20].map { date(2027, 4, $0, ContractSchedule.hour) })
        let onTheLastDay = mowing(h, weekdays: [5])                                // Thursdays: Apr 29 is its last day
        #expect(ContractSchedule.dates(of: onTheLastDay, now: date(2027, 3, 20), calendar: calendar).last
                == date(2027, 4, 29, ContractSchedule.hour))
    }

    @Test func bookingPutsItsVisitsOnTheScheduleAtEachPlace() throws {
        let h = try Harness(stopCount: 0)
        h.client.goalMinutes = 30
        let rental = Property(label: "Rental", address: "9 Elm St", operatorID: "op")
        h.context.insert(rental)
        rental.client = h.client
        let contract = mowing(h)
        contract.placeIDs = [h.client.id.uuidString, rental.id.uuidString]
        let now = date(2027, 3, 20)
        #expect(ContractSchedule.book(contract, in: h.context, now: now, calendar: calendar) == 8)
        let visits = ContractSchedule.visitsAhead(of: contract, in: h.context, now: now, calendar: calendar)
        #expect(visits.count == 8)
        let atRental = visits.filter { $0.propertyID == rental.id.uuidString }
        #expect(atRental.count == 4 && atRental.allSatisfy { $0.clientAddress == "9 Elm St" })
        let first = try #require(visits.min { $0.scheduledDate < $1.scheduledDate })
        #expect(first.expectedServiceIDs == ["mow"] && first.visitReason == "Mowing")
        #expect(first.isRecurring && first.recurrenceEndDate == contract.endDate)
        #expect(visits.first { $0.propertyID.isEmpty }?.estimatedMinutes == 30)
    }

    // Booked again (its day changed): the visits not done yet are replaced;
    // done ones stay.
    @Test func bookingAgainReplacesTheVisitsNotDone() throws {
        let h = try Harness(stopCount: 0)
        let contract = mowing(h)
        ContractSchedule.book(contract, in: h.context, now: date(2027, 3, 20), calendar: calendar)
        let done = try #require(ContractSchedule.visitsAhead(of: contract, in: h.context, now: date(2027, 3, 20),
                                                             calendar: calendar).min { $0.scheduledDate < $1.scheduledDate })
        done.status = .completed
        contract.scheduleWeekdays = [4]                                           // Wednesdays now
        #expect(ContractSchedule.book(contract, in: h.context, now: date(2027, 4, 8), calendar: calendar) == 3)
        let all = try h.context.fetch(FetchDescriptor<ScheduledVisit>())
        #expect(all.count == 4)
        #expect(all.contains { $0.id == done.id })
    }

    @Test func onlyASignedContractInForceBooks() throws {
        let h = try Harness(stopCount: 0)
        let contract = mowing(h)
        contract.signedAt = nil
        #expect(ContractSchedule.book(contract, in: h.context, now: date(2027, 3, 20), calendar: calendar) == 0)
        contract.signedAt = date(2027, 3, 1)
        contract.scheduleWeekdays = []
        #expect(!ContractSchedule.canBook(contract, now: date(2027, 3, 20)))
        contract.scheduleWeekdays = [3]
        #expect(!ContractSchedule.canBook(contract, now: date(2027, 5, 10)))       // ended
        contract.cancelledAt = date(2027, 3, 10)
        #expect(!ContractSchedule.canBook(contract, now: date(2027, 3, 20)))       // cancelled
        contract.cancelledAt = nil
        h.client.isActive = false
        #expect(!ContractSchedule.canBook(contract, now: date(2027, 3, 20)))       // inactive client
    }

    // Done or skipped today, then booked again: that day keeps its one visit.
    @Test func bookingAgainLeavesDaysDoneOrSkipped() throws {
        let h = try Harness(stopCount: 0)
        let contract = mowing(h)
        ContractSchedule.book(contract, in: h.context, now: date(2027, 3, 20), calendar: calendar)
        let visits = try h.context.fetch(FetchDescriptor<ScheduledVisit>()).sorted { $0.scheduledDate < $1.scheduledDate }
        visits[1].status = .completed                                              // Apr 13, done at 10
        visits[2].status = .skipped                                                // Apr 20, away
        let now = date(2027, 4, 13, 15)
        #expect(ContractSchedule.plan(contract, in: h.context, now: now, calendar: calendar).keptDays == 2)
        #expect(ContractSchedule.book(contract, in: h.context, now: now, calendar: calendar) == 1)    // Apr 27 only
        let onThe13th = try h.context.fetch(FetchDescriptor<ScheduledVisit>())
            .filter { calendar.isDate($0.scheduledDate, inSameDayAs: date(2027, 4, 13)) }
        #expect(onThe13th.count == 1)
    }

    // A client already visited every Tuesday by hand isn't booked twice.
    @Test func bookingLeavesDaysWithAVisitBookedByHand() throws {
        let h = try Harness(stopCount: 0)
        let byHand = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                    clientAddress: h.client.address, scheduledDate: date(2027, 4, 6, 9))
        byHand.seriesID = "series-by-hand"
        h.context.insert(byHand)
        let cancelled = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                       clientAddress: h.client.address, scheduledDate: date(2027, 4, 13, 9))
        cancelled.status = .cancelled
        h.context.insert(cancelled)
        #expect(ContractSchedule.book(mowing(h), in: h.context, now: date(2027, 3, 20), calendar: calendar) == 3)
    }

    // Visits switched off: the ones it booked after today come off.
    @Test func switchingVisitsOffTakesThemOff() throws {
        let h = try Harness(stopCount: 0)
        let contract = mowing(h)
        ContractSchedule.book(contract, in: h.context, now: date(2027, 3, 20), calendar: calendar)
        var draft = Contracts.Draft(contract)
        draft.scheduleWeekdays = []
        Contracts.save(draft, to: contract, of: h.client, in: h.context)
        #expect(ContractSchedule.visitsAhead(of: contract, in: h.context, now: date(2027, 3, 20), calendar: calendar).isEmpty)
    }

    // Cancelled: its visits after today come off, and its series stop.
    @Test func cancellingTakesOffTheVisitsAhead() throws {
        let h = try Harness(stopCount: 0)
        let contract = mowing(h)
        ContractSchedule.book(contract, in: h.context, now: date(2027, 3, 20), calendar: calendar)
        Contracts.cancel(contract, in: h.context, now: date(2027, 4, 13, 12))
        let left = try h.context.fetch(FetchDescriptor<ScheduledVisit>())
        #expect(left.map(\.scheduledDate).sorted() == [6, 13].map { date(2027, 4, $0, ContractSchedule.hour) })
        #expect(left.allSatisfy { ($0.recurrenceEndDate ?? .distantFuture) <= date(2027, 4, 13, 23) })
    }

    // Ended earlier: its visits after the new last day come off.
    @Test func endingEarlierTakesOffTheVisitsAfter() throws {
        let h = try Harness(stopCount: 0)
        let contract = mowing(h)
        ContractSchedule.book(contract, in: h.context, now: date(2027, 3, 20), calendar: calendar)
        var draft = Contracts.Draft(contract)
        draft.endDate = date(2027, 4, 15)
        Contracts.save(draft, to: contract, of: h.client, in: h.context)
        #expect(try h.context.fetch(FetchDescriptor<ScheduledVisit>()).count == 2)
    }
}
