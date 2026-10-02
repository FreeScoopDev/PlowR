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

    /// Whether every place of `clientID` under a snow contract on `day` is
    /// marked: only then is the client left out of the storm. A place checked
    /// at the stop doesn't speak for their other places.
    static func isClientMarked(_ clientID: String, on day: Date, contracts: [Contract], services: [ServiceItem],
                               in checks: [TriggerCheck], calendar: Calendar = .current) -> Bool {
        let places = contractPlaces(of: clientID, on: day, contracts: contracts, services: services, calendar: calendar)
        return !places.isEmpty
            && places.allSatisfy { isMarked(clientID, placeID: $0, on: day, in: checks, calendar: calendar) }
    }

    /// Whether any of `clientID`'s marks on `day` is a check at the stop.
    static func hasStopCheck(_ clientID: String, on day: Date, in checks: [TriggerCheck],
                             calendar: Calendar = .current) -> Bool {
        checks.contains { $0.clientID == clientID && $0.isFromStop && calendar.isDate($0.day, inSameDayAs: day) }
    }

    /// The places of `clientID` that their snow contracts in force on `day`
    /// cover: where a storm card's mark applies. A snow contract has a
    /// trigger or a snow service, as in StormWatch.
    static func contractPlaces(of clientID: String, on day: Date, contracts: [Contract], services: [ServiceItem],
                               calendar: Calendar = .current) -> [String] {
        var places: [String] = []
        for contract in contracts where contract.clientID == clientID
            && (contract.triggerInches > 0 || Contracts.coversSnow(Set(contract.serviceIDs), catalog: services)) {
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

    /// The check made at the stop on a route: the stop's place, on `day`
    /// (the run's: a storm route past midnight is the storm day's work, as
    /// in the Service Log), with the run and the GPS arrival if one was caught.
    static func checkAtStop(_ stop: RouteStop, of client: Client, run: UUID?, routeName: String, arrivedAt: Date?,
                            day: Date, note: String, operatorID: String, in context: ModelContext, now: Date = .now,
                            calendar: Calendar = .current) -> TriggerCheck {
        let check = TriggerCheck(operatorID: operatorID, clientID: client.id.uuidString, clientName: client.name,
                                 placeID: Place.id(of: client, propertyID: stop.propertyID),
                                 day: calendar.startOfDay(for: day))
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
    /// every copy of a mark by hand, from any device. A check made at the stop
    /// stays: it's the crew's record, with its photos, removed only one by one
    /// on the contract's page.
    static func unmark(_ clientID: String, places: [String]? = nil, on day: Date, in context: ModelContext,
                       calendar: Calendar = .current) {
        let all = (try? context.fetch(FetchDescriptor<TriggerCheck>())) ?? []
        for check in all where check.clientID == clientID && !check.isFromStop
            && calendar.isDate(check.day, inSameDayAs: day) && (places?.contains(check.placeID) ?? true) {
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

    /// The contract trigger Below Trigger offers at `stop` on `day`: a snow
    /// contract covering the stop's own place, and snow work expected there
    /// (a snow service, or none set). Not a July mowing stop under a
    /// year-round contract, nor a place the contract doesn't cover.
    static func trigger(for stop: RouteStop, client: Client, on day: Date, contracts: [Contract],
                        services: [ServiceItem]) -> StormWatch.Trigger? {
        guard !stop.isCustomStop, client.isActive else { return nil }
        let place = Place.id(of: client, propertyID: stop.propertyID)
        let clientID = client.id.uuidString
        let covering = contracts.filter {
            $0.clientID == clientID && Contracts.covers($0, placeID: place, on: day)
                && ($0.triggerInches > 0 || Contracts.coversSnow(Set($0.serviceIDs), catalog: services))
        }
        guard let contract = covering.min(by: { $0.triggerInches < $1.triggerInches }) else { return nil }
        let snowIDs = Set(services.filter { $0.category == ServiceCatalog.snowKey }.map(\.id.uuidString))
        let expected = StopServices.expected(for: stop, client: client)
        guard expected.isEmpty || expected.contains(where: snowIDs.contains) else { return nil }
        return StormWatch.Trigger(clientID: clientID, clientName: client.name, inches: contract.triggerInches)
    }

    /// What Below Trigger did at a stop.
    enum PassOutcome: Equatable {
        /// Moved on to the next stop, or past the last one (the recap).
        case movedOn, finishedRoute
        /// The stop was already behind (a double tap, Control Center): nothing kept.
        case alreadyPast
        /// Another device changed the route: the check is kept (it's about the
        /// place), but the route didn't move on.
        case routeChanged
    }

    /// Below Trigger, saved at `stop`: moves the route past it without
    /// crediting a visit (ActiveRouteStore.passCurrentStop), then keeps the
    /// check with the note, the photos and the GPS arrival if one was caught.
    @discardableResult
    static func passBelowTrigger(_ stop: RouteStop, of client: Client, store: ActiveRouteStore, routeName: String,
                                 operatorID: String, note: String, photos: [CapturedPhoto], in context: ModelContext,
                                 now: Date = .now, calendar: Calendar = .current) -> PassOutcome {
        if store.isBehindCurrentStop(stop.id) { return .alreadyPast }
        let arrivedAt = store.currentStopID == stop.id ? store.site.arrivedAt : nil
        let run = store.runID
        let day = store.runStartedAt ?? now
        let result = store.passCurrentStop(expecting: stop.id)
        let outcome: PassOutcome
        switch result {
        case .noActiveRoute, .allStopsAlreadyDone: return .alreadyPast
        case .stopChanged: outcome = .routeChanged
        case .finishedLastStop: outcome = .finishedRoute
        case .advanced: outcome = .movedOn
        }
        let check = checkAtStop(stop, of: client, run: run, routeName: routeName,
                                arrivedAt: outcome == .routeChanged ? nil : arrivedAt, day: day, note: note,
                                operatorID: operatorID, in: context, now: now, calendar: calendar)
        for captured in photos {
            guard let photo = StopPhoto.make(from: captured, isBefore: true, operatorID: operatorID,
                                             clientID: client.id.uuidString, routeID: stop.route?.id.uuidString ?? "",
                                             recordID: "") else { continue }
            photo.checkID = check.id.uuidString
            context.insert(photo)
        }
        try? context.save()
        return outcome
    }

    /// A client's checks, oldest first.
    static func of(clientID: String, in context: ModelContext) -> [TriggerCheck] {
        let descriptor = FetchDescriptor<TriggerCheck>(predicate: #Predicate { $0.clientID == clientID })
        return ((try? context.fetch(descriptor)) ?? []).sorted { $0.day < $1.day }
    }
}
