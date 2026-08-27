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

        var ordered: [(origIdx: Int, wp: Waypoint)] = [withGPS.removeFirst()]
        while !withGPS.isEmpty {
            let last = ordered.last!.wp
            let nearestIdx = withGPS.indices.min { i, j in
                haversineKm(last, withGPS[i].wp) < haversineKm(last, withGPS[j].wp)
            }!
            ordered.append(withGPS.remove(at: nearestIdx))
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
