import Foundation

/// The run about to start from a route's page: the route's stops, less the
/// ones left out today (Skip Today). The page's load-out, Message All and
/// Start button all read it, so a skipped client isn't counted, loaded for,
/// or texted "we'll be there today". Start From Here leaves out the stops
/// before the one chosen, too.
struct TodaysRun: Equatable {
    /// The route's stops, in order.
    var routeStops: [UUID]
    /// Left out today by hand. IDs no longer on the route are ignored.
    var skippedByHand: Set<UUID> = []
    /// Stops whose place is marked below its contract's snow trigger today
    /// (TriggerCheck): left out unless included anyway.
    var belowTrigger: Set<UUID> = []
    var includedAnyway: Set<UUID> = []

    init(routeStops: [UUID], skipped: Set<UUID> = [], belowTrigger: Set<UUID> = [],
         includedAnyway: Set<UUID> = []) {
        self.routeStops = routeStops
        self.skippedByHand = skipped
        self.belowTrigger = belowTrigger
        self.includedAnyway = includedAnyway
    }

    /// Left out today: by hand, or below trigger and not included anyway.
    var skipped: Set<UUID> { skippedByHand.union(belowTrigger.subtracting(includedAnyway)) }

    /// The skipped stops still on the route.
    var skippedOnRoute: Set<UUID> { skipped.intersection(routeStops) }

    /// Whether `stop` is in today's run. The one rule for "skipped".
    func isIncluded(_ stop: UUID) -> Bool { !skipped.contains(stop) }

    /// Today's stops, in order.
    var stops: [UUID] { routeStops.filter(isIncluded) }

    var startTitle: String {
        skippedOnRoute.isEmpty ? "Start Route" : "Start Route · \(stops.count) of \(routeStops.count) Stops"
    }

    /// Skips an included stop, or includes a skipped one, whichever way it
    /// came to be skipped (by hand, below trigger, or both).
    mutating func toggle(_ stop: UUID) {
        if skipped.contains(stop) {
            skippedByHand.remove(stop)
            if belowTrigger.contains(stop) { includedAnyway.insert(stop) }
        } else if belowTrigger.contains(stop) {
            includedAnyway.remove(stop)
        } else {
            skippedByHand.insert(stop)
        }
    }

    /// What to leave out when starting from the stop at `index`: the stops
    /// before it, and any skipped.
    func skipping(from index: Int) -> Set<UUID> {
        skippedOnRoute.union(routeStops.prefix(max(0, index)))
    }
}

extension TodaysRun {
    /// A route's run as its page opens it on `day`: nothing skipped by hand,
    /// the stops marked below their contract's trigger that day left out.
    /// The route page's Start and Schedule's Start Route both begin this run.
    @MainActor
    static func opening(_ route: PlowRoute, on day: Date, checks: [TriggerCheck],
                        calendar: Calendar = .current) -> TodaysRun {
        let stops = route.sortedStops
        let below = stops.filter {
            TriggerChecks.isMarked($0.clientID.uuidString, placeID: Place.id(ofStop: $0), on: day, in: checks,
                                   calendar: calendar)
        }
        return TodaysRun(routeStops: stops.map(\.id), belowTrigger: Set(below.map(\.id)))
    }
}

/// What Schedule's "Route Created" alert offers after Create Route.
enum RouteFromDay {
    /// Start Route, beside Open Route: only for a route made from today's
    /// visits, while no route is running, with a stop left to run today.
    static func offersStart(day: Date, now: Date, routeRunning: Bool, stopsToRun: Int,
                            calendar: Calendar = .current) -> Bool {
        !routeRunning && stopsToRun > 0 && calendar.isDate(day, inSameDayAs: now)
    }
}
