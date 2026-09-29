import Foundation

/// How a route's current or last run reads in the route list and on the
/// dashboard: how many of its stops are done, and whether it's running now.
///
/// "Running" comes from the route store, not from the counts. Worked out from
/// the counts, a route ended part-way stayed orange "in progress" for good.
struct RouteRunSummary: Equatable {
    let total: Int
    let done: Int
    let isRunning: Bool

    init(stops: [RouteStop], isRunning: Bool) {
        total = stops.count
        done = stops.filter { $0.actualMinutes > 0 }.count
        self.isRunning = isRunning
    }

    /// The last run finished every stop, and the route isn't running now.
    var isDone: Bool { !isRunning && total > 0 && done == total }
}
