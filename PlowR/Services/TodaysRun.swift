import Foundation

/// The run about to start from a route's page: the route's stops, less the
/// ones left out today (Skip Today). The page's load-out, Message All and
/// Start button all read it, so a skipped client isn't counted, loaded for,
/// or texted "we'll be there today". Start From Here leaves out the stops
/// before the one chosen, too.
struct TodaysRun: Equatable {
    /// The route's stops, in order.
    var routeStops: [UUID]
    /// Left out today. IDs no longer on the route are ignored.
    var skipped: Set<UUID> = []

    /// The skipped stops still on the route.
    var skippedOnRoute: Set<UUID> { skipped.intersection(routeStops) }

    /// Whether `stop` is in today's run. The one rule for "skipped".
    func isIncluded(_ stop: UUID) -> Bool { !skipped.contains(stop) }

    /// Today's stops, in order.
    var stops: [UUID] { routeStops.filter(isIncluded) }

    var startTitle: String {
        skippedOnRoute.isEmpty ? "Start Route" : "Start Route · \(stops.count) of \(routeStops.count) Stops"
    }

    mutating func toggle(_ stop: UUID) {
        if skipped.contains(stop) { skipped.remove(stop) } else { skipped.insert(stop) }
    }

    /// What to leave out when starting from the stop at `index`: the stops
    /// before it, and any skipped.
    func skipping(from index: Int) -> Set<UUID> {
        skippedOnRoute.union(routeStops.prefix(max(0, index)))
    }
}
