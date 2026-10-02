import Foundation
import SwiftData

/// Days a client's place didn't reach their contract's snow trigger
/// (TriggerCheck): marking, unmarking, and reading them. Two devices can
/// each mark the same day before iCloud brings the other's: any mark counts,
/// and unmarking removes them all.
enum TriggerChecks {
    /// Whether `checks` mark `placeID` of `clientID` below trigger on `day`.
    /// No place: any of the client's.
    static func isMarked(_ clientID: String, placeID: String? = nil, on day: Date, in checks: [TriggerCheck],
                         calendar: Calendar = .current) -> Bool {
        checks.contains {
            $0.clientID == clientID && (placeID == nil || $0.placeID == placeID)
                && calendar.isDate($0.day, inSameDayAs: day)
        }
    }

    /// The clients with any place marked on `day`.
    static func markedClients(on day: Date, in checks: [TriggerCheck], operatorID: String,
                              calendar: Calendar = .current) -> Set<String> {
        Set(checks.filter { $0.operatorID == operatorID && calendar.isDate($0.day, inSameDayAs: day) }.map(\.clientID))
    }

    /// The places of `clientID` that their snow contracts in force on `day`
    /// cover: where a storm card's mark applies.
    static func contractPlaces(of clientID: String, on day: Date, contracts: [Contract],
                               calendar: Calendar = .current) -> [String] {
        var places: [String] = []
        for contract in contracts where contract.clientID == clientID {
            for place in contract.placeIDs where !places.contains(place)
                && Contracts.covers(contract, placeID: place, on: day, calendar: calendar) {
                places.append(place)
            }
        }
        return places
    }

    /// Marks these places below trigger on `day`, by hand. Places already
    /// marked aren't marked twice.
    @discardableResult
    static func mark(clientID: String, clientName: String, places: [String], on day: Date, operatorID: String,
                     in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> [TriggerCheck] {
        let existing = (try? context.fetch(FetchDescriptor<TriggerCheck>())) ?? []
        var made: [TriggerCheck] = []
        for place in places where !isMarked(clientID, placeID: place, on: day, in: existing, calendar: calendar) {
            let check = TriggerCheck(operatorID: operatorID, clientID: clientID, clientName: clientName,
                                     placeID: place, day: calendar.startOfDay(for: day))
            check.checkedAt = now
            context.insert(check)
            made.append(check)
        }
        try? context.save()
        return made
    }

    /// The check made at the stop on a route: the stop's place, today, with
    /// the run and the GPS arrival if one was caught.
    static func checkAtStop(_ stop: RouteStop, of client: Client, run: UUID?, routeName: String, arrivedAt: Date?,
                            note: String, operatorID: String, in context: ModelContext, now: Date = .now,
                            calendar: Calendar = .current) -> TriggerCheck {
        let check = TriggerCheck(operatorID: operatorID, clientID: client.id.uuidString, clientName: client.name,
                                 placeID: Place.id(of: client, propertyID: stop.propertyID),
                                 day: calendar.startOfDay(for: now))
        check.sourceRaw = "stop"
        check.checkedAt = now
        check.runID = run?.uuidString ?? ""
        check.stopID = stop.id.uuidString
        check.routeName = routeName
        check.arrivedAt = arrivedAt
        check.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(check)
        return check
    }

    /// Unmarks these places (all, without places) of `clientID` on `day`:
    /// every copy, from any device, and its photos.
    static func unmark(_ clientID: String, places: [String]? = nil, on day: Date, in context: ModelContext,
                       calendar: Calendar = .current) {
        let all = (try? context.fetch(FetchDescriptor<TriggerCheck>())) ?? []
        for check in all where check.clientID == clientID && calendar.isDate(check.day, inSameDayAs: day)
            && (places?.contains(check.placeID) ?? true) {
            delete(check, in: context)
        }
        try? context.save()
    }

    /// Deletes a check and its photos.
    static func delete(_ check: TriggerCheck, in context: ModelContext) {
        for photo in photos(of: check, in: context) { context.delete(photo) }
        context.delete(check)
    }

    static func photos(of check: TriggerCheck, in context: ModelContext) -> [StopPhoto] {
        let id = check.id.uuidString
        let descriptor = FetchDescriptor<StopPhoto>(predicate: #Predicate { $0.checkID == id })
        return StopPhoto.ordered((try? context.fetch(descriptor)) ?? [])
    }

    /// A client's checks, oldest first.
    static func of(clientID: String, in context: ModelContext) -> [TriggerCheck] {
        let descriptor = FetchDescriptor<TriggerCheck>(predicate: #Predicate { $0.clientID == clientID })
        return ((try? context.fetch(descriptor)) ?? []).sorted { $0.day < $1.day }
    }
}
