import Foundation

enum RouteOptimizer {
    struct Waypoint {
        let latitude: Double
        let longitude: Double
        var hasGPS: Bool { latitude != 0 || longitude != 0 }
    }

    /// Nearest-neighbor reordering. Returns original indices in optimized visit order.
    /// Waypoints without GPS (both lat and lon == 0) are appended after optimized stops.
    static func nearestNeighborOrder(of waypoints: [Waypoint]) -> [Int] {
        var withGPS = waypoints.enumerated()
            .filter { $0.element.hasGPS }
            .map { (origIdx: $0.offset, wp: $0.element) }
        let withoutGPS = waypoints.enumerated()
            .filter { !$0.element.hasGPS }
            .map { $0.offset }

        guard withGPS.count >= 2 else {
            return withGPS.map(\.origIdx) + withoutGPS
        }

        var current = withGPS.removeFirst()
        var ordered: [(origIdx: Int, wp: Waypoint)] = [current]
        while let nearestIdx = withGPS.indices.min(by: { i, j in
            haversineKm(current.wp, withGPS[i].wp) < haversineKm(current.wp, withGPS[j].wp)
        }) {
            current = withGPS.remove(at: nearestIdx)
            ordered.append(current)
        }

        return ordered.map(\.origIdx) + withoutGPS
    }

    // MARK: - Driving times

    /// What a travel-time provider answers for one leg.
    enum TravelTime: Equatable {
        /// The driving time, in seconds.
        case seconds(TimeInterval)
        /// No answer for this leg (no route found, a network error).
        case unavailable
        /// The map service says it is throttling this app: stop asking.
        case throttled
    }

    /// Asks for the driving time from one waypoint to another.
    typealias TravelTimeProvider = (_ from: Waypoint, _ to: Waypoint) async -> TravelTime

    /// The order a driving-time optimization came to, in original indices,
    /// and how many of its legs used the straight-line estimate.
    struct DrivingOrder: Equatable {
        let order: [Int]
        /// Legs between stops with GPS in `order`: one fewer than those stops.
        let legs: Int
        /// Of those, how many were scored by the straight-line estimate.
        let estimatedLegs: Int
    }

    /// At each step only this many of the nearest remaining stops (by
    /// straight line) are asked about: asking about every one is about
    /// n²/2 requests, and MapKit throttles an app after a few dozen a minute.
    static let candidatesPerStep = 5
    /// After this many unavailable answers in a row, stop asking for the run.
    static let unavailableCutoff = 3
    /// Roads wind: a drive is about this much longer than the straight line.
    static let roadFactor = 1.3
    /// Average driving speed for the estimate, km/h.
    static let averageSpeedKmh = 40.0

    /// The estimated driving time in seconds from the straight-line
    /// distance, so an estimated leg compares with a real one in one unit.
    static func estimatedSeconds(_ a: Waypoint, _ b: Waypoint) -> TimeInterval {
        haversineKm(a, b) * roadFactor / averageSpeedKmh * 3_600
    }

    /// Nearest-neighbour by driving time. The first stop with GPS stays
    /// first; stops without GPS keep their order after the rest. At each step
    /// only the `candidatesPerStep` nearest remaining stops by straight line
    /// are asked about, one request at a time, each pair at most once. A leg
    /// with no answer is scored by `estimatedSeconds`; after a throttled
    /// answer or `unavailableCutoff` unavailable ones in a row, the provider
    /// isn't asked again this run. Throws `CancellationError` if the task is
    /// cancelled, so a cancelled run returns no order at all.
    static func drivingOrder(of waypoints: [Waypoint],
                             travelTime: TravelTimeProvider) async throws -> DrivingOrder {
        var remaining = waypoints.indices.filter { waypoints[$0].hasGPS }
        let withoutGPS = waypoints.indices.filter { !waypoints[$0].hasGPS }
        guard remaining.count >= 2 else {
            return DrivingOrder(order: remaining + withoutGPS, legs: 0, estimatedLegs: 0)
        }

        var cache: [Pair: TravelTime] = [:]
        var asking = true
        var unavailableInARow = 0
        var estimatedLegs = 0

        var current = remaining.removeFirst()
        var ordered = [current]
        while !remaining.isEmpty {
            try Task.checkCancellation()
            let from = waypoints[current]
            let candidates = remaining
                .sorted { haversineKm(from, waypoints[$0]) < haversineKm(from, waypoints[$1]) }
                .prefix(candidatesPerStep)

            var best: (index: Int, seconds: TimeInterval, estimated: Bool)?
            for candidate in candidates {
                let to = waypoints[candidate]
                let pair = Pair(from: current, to: candidate)
                var answer = cache[pair]
                if answer == nil, asking {
                    let asked = await travelTime(from, to)
                    try Task.checkCancellation()
                    cache[pair] = asked
                    answer = asked
                    switch asked {
                    case .seconds: unavailableInARow = 0
                    case .unavailable:
                        unavailableInARow += 1
                        if unavailableInARow >= unavailableCutoff { asking = false }
                    case .throttled: asking = false
                    }
                }
                let seconds: TimeInterval
                let estimated: Bool
                if case .seconds(let real)? = answer {
                    seconds = real
                    estimated = false
                } else {
                    seconds = estimatedSeconds(from, to)
                    estimated = true
                }
                if best.map({ seconds < $0.seconds }) ?? true {
                    best = (candidate, seconds, estimated)
                }
            }

            guard let chosen = best else { break }
            if chosen.estimated { estimatedLegs += 1 }
            remaining.removeAll { $0 == chosen.index }
            ordered.append(chosen.index)
            current = chosen.index
        }

        return DrivingOrder(order: ordered + withoutGPS, legs: ordered.count - 1, estimatedLegs: estimatedLegs)
    }

    /// One leg, by original indices, for the per-run cache.
    private struct Pair: Hashable {
        let from: Int
        let to: Int
    }

    /// Great-circle distance in kilometres (Haversine formula).
    static func haversineKm(_ a: Waypoint, _ b: Waypoint) -> Double {
        let R = 6_371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sinLat = sin(dLat / 2)
        let sinLon = sin(dLon / 2)
        let h = sinLat * sinLat + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinLon * sinLon
        return 2 * R * asin(sqrt(h))
    }
}
