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
