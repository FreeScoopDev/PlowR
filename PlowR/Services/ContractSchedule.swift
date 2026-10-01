import Foundation
import SwiftData

/// The visits a contract books itself: on its weekdays, every so many
/// weeks, at each place it covers, through its last day. Booked by a tap
/// (Book Visits on the contract's page), never in the background: several
/// devices booking on their own would each book the season. They're
/// ordinary repeating visits (one series per place), so the Schedule,
/// routes and the calendar treat them like any other, and each series
/// continues itself as its visits are done.
enum ContractSchedule {
    /// Visits are booked at this hour; each can be moved on the Schedule.
    static let hour = 8

    /// The series ID of the contract's visits at a place: tells them apart
    /// from visits booked by hand.
    static func seriesID(_ contract: Contract, placeID: String) -> String {
        "\(prefix(contract))\(placeID)"
    }

    private static func prefix(_ contract: Contract) -> String { "contract:\(contract.id.uuidString):" }

    static func hasSchedule(_ contract: Contract) -> Bool { !contract.scheduleWeekdays.isEmpty }

    /// "Every Tuesday", "Every 2 weeks on Tuesday and Friday".
    static func summary(of contract: Contract, calendar: Calendar = .current) -> String {
        let names = contract.scheduleWeekdays.sorted().compactMap { day -> String? in
            guard (1...7).contains(day) else { return nil }
            return calendar.weekdaySymbols[day - 1]
        }
        guard !names.isEmpty else { return "No visits booked by the contract" }
        let days = names.formatted(.list(type: .and))
        return contract.scheduleIntervalWeeks > 1 ? "Every \(contract.scheduleIntervalWeeks) weeks on \(days)" : "Every \(days)"
    }

    /// The rule its visits repeat by.
    static func rule(of contract: Contract) -> RecurrenceRule {
        RecurrenceRule(type: .weekly, interval: max(1, contract.scheduleIntervalWeeks),
                       weekdays: Set(contract.scheduleWeekdays), endDate: contract.endDate)
    }

    /// Its visit dates from today on (at `hour`), counted from its start so
    /// "every 2 weeks" keeps the same weeks whenever it's booked.
    static func dates(of contract: Contract, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        guard hasSchedule(contract) else { return [] }
        let start = calendar.startOfDay(for: contract.startDate)
        var first: Date?
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if contract.scheduleWeekdays.contains(calendar.component(.weekday, from: day)) { first = day; break }
        }
        guard let firstDay = first,
              let firstVisit = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: firstDay),
              let horizon = calendar.date(byAdding: RecurrenceRule.upFrontHorizon, to: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        return rule(of: contract).occurrences(from: firstVisit, limit: 500, horizon: horizon, calendar: calendar)
            .filter { $0 >= today }
    }

    /// Whether Book Visits is offered: a schedule, signed and not over, the
    /// client still on file and active (an inactive client is off every
    /// route, and isn't booked a season of visits).
    static func canBook(_ contract: Contract, now: Date = .now) -> Bool {
        hasSchedule(contract) && contract.client?.isActive == true && Contracts.status(of: contract, now: now).isInForce
    }

    /// What booking would do: the visits to book, and how many of its days
    /// are left as they are because there's already a visit at that place
    /// that day: one of its own done, skipped or cancelled (booking again
    /// never undoes that), or one booked by hand. Its own still to do are
    /// replaced, so they don't count.
    struct Plan {
        var visits: [(place: Place, date: Date)] = []
        var keptDays = 0
    }

    static func plan(_ contract: Contract, in context: ModelContext, now: Date = .now,
                     calendar: Calendar = .current) -> Plan {
        guard let client = contract.client else { return Plan() }
        let clientID = client.id.uuidString
        let today = calendar.startOfDay(for: now)
        let theirs = (try? context.fetch(FetchDescriptor<ScheduledVisit>(
            predicate: #Predicate { $0.clientID == clientID && $0.scheduledDate >= today }))) ?? []
        let ownPrefix = prefix(contract)
        let dates = dates(of: contract, now: now, calendar: calendar)
        var plan = Plan()
        for placeID in contract.placeIDs {
            guard let place = Place.of(client, propertyID: placeID) else { continue }
            let taken = Set(theirs.filter { visit in
                guard Place.id(of: client, propertyID: visit.propertyID) == place.id else { return false }
                return visit.seriesID.hasPrefix(ownPrefix) ? visit.status != .scheduled : visit.status != .cancelled
            }.map { calendar.startOfDay(for: $0.scheduledDate) })
            for date in dates {
                if taken.contains(calendar.startOfDay(for: date)) {
                    plan.keptDays += 1
                } else {
                    plan.visits.append((place, date))
                }
            }
        }
        return plan
    }

    /// Its visits from today on not done yet, at every place.
    static func visitsAhead(of contract: Contract, in context: ModelContext, now: Date = .now,
                            calendar: Calendar = .current) -> [ScheduledVisit] {
        let clientID = contract.clientID
        let today = calendar.startOfDay(for: now)
        let prefix = prefix(contract)
        let visits = (try? context.fetch(FetchDescriptor<ScheduledVisit>(
            predicate: #Predicate { $0.clientID == clientID && $0.scheduledDate >= today }))) ?? []
        return visits.filter { $0.seriesID.hasPrefix(prefix) && $0.status == .scheduled }
    }

    /// Books its visits from today on, at each of its places, replacing
    /// those it booked before that aren't done yet (Book Visits; again after
    /// its days change). Returns how many were booked.
    @discardableResult
    static func book(_ contract: Contract, in context: ModelContext, now: Date = .now,
                     calendar: Calendar = .current) -> Int {
        guard canBook(contract, now: now), let client = contract.client else { return 0 }
        let plan = plan(contract, in: context, now: now, calendar: calendar)
        visitsAhead(of: contract, in: context, now: now, calendar: calendar).forEach { context.delete($0) }
        for (place, date) in plan.visits {
                let visit = ScheduledVisit(operatorID: contract.operatorID, clientID: client.id.uuidString,
                                           clientName: client.name, clientAddress: place.address, scheduledDate: date)
                visit.propertyID = place.storedID
                visit.expectedServiceIDs = contract.serviceIDs
                visit.estimatedMinutes = place.goalMinutes
                visit.notes = place.stopNotes
                visit.visitReason = contract.name
                visit.isRecurring = true
                visit.recurrenceType = .weekly
                visit.recurrenceInterval = max(1, contract.scheduleIntervalWeeks)
                visit.recurrenceWeekdays = contract.scheduleWeekdays.sorted()
                visit.recurrenceEndDate = contract.endDate
                visit.seriesID = seriesID(contract, placeID: place.id)
                context.insert(visit)
        }
        try? context.save()
        return plan.visits.count
    }

    /// Takes off its visits not done yet dated after `day` (the day it was
    /// cancelled, or its new last day), and stops its series there.
    static func removeVisits(of contract: Contract, after day: Date, in context: ModelContext,
                             calendar: Calendar = .current) {
        let cutoff = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cutoff) else { return }
        let clientID = contract.clientID
        let prefix = prefix(contract)
        let visits = ((try? context.fetch(FetchDescriptor<ScheduledVisit>(
            predicate: #Predicate { $0.clientID == clientID }))) ?? []).filter { $0.seriesID.hasPrefix(prefix) }
        for visit in visits {
            if visit.scheduledDate >= nextDay, visit.status == .scheduled {
                context.delete(visit)
            } else {
                visit.recurrenceEndDate = cutoff
            }
        }
    }
}
