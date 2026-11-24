import Foundation

/// A route's stop order, keyed by stop ID: taken before and after Optimize
/// Order, so its Undo can put the order back (UndoCenter.optimized).
struct StopOrderSnapshot: Equatable {
    let orders: [UUID: Int]

    init(orders: [UUID: Int]) {
        self.orders = orders
    }

    init(_ stops: [RouteStop]) {
        orders = Dictionary(stops.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
    }

    /// Puts this order back on `stops`, if they still stand exactly as
    /// `after`: the same stops, each in the place Optimize gave it. A stop
    /// moved by hand, added or removed since (here or by sync) leaves
    /// everything as it is, and returns false.
    func restore(on stops: [RouteStop], ifStill after: StopOrderSnapshot) -> Bool {
        guard StopOrderSnapshot(stops) == after, stops.count == after.orders.count,
              Set(orders.keys) == Set(after.orders.keys) else { return false }
        for stop in stops {
            if let order = orders[stop.id] { stop.order = order }
        }
        return true
    }
}
