import Testing
@testable import PlowR

struct RouteOptimizerTests {

    private typealias WP = RouteOptimizer.Waypoint

    // MARK: - nearestNeighborOrder

    // Three stops in non-optimal order: starting from A (lon 0), the nearest GPS stop is
    // B (lon 1) not C (lon 3). Expect output indices [0, 2, 1] — A first, then B, then C.
    @Test func nearestNeighborOrder_reordersToShortestPath() {
        let waypoints = [
            WP(latitude: 1, longitude: 0),  // index 0 – start (A)
            WP(latitude: 1, longitude: 3),  // index 1 – far   (C)
            WP(latitude: 1, longitude: 1),  // index 2 – near  (B)
        ]
        let order = RouteOptimizer.nearestNeighborOrder(of: waypoints)
        #expect(order == [0, 2, 1])
    }

    @Test func nearestNeighborOrder_emptyInput_returnsEmpty() {
        #expect(RouteOptimizer.nearestNeighborOrder(of: []).isEmpty)
    }

    @Test func nearestNeighborOrder_singleStop_returnsSelf() {
        let order = RouteOptimizer.nearestNeighborOrder(of: [WP(latitude: 42, longitude: -71)])
        #expect(order == [0])
    }

    // Stops with no GPS (lat == 0, lon == 0) must be appended after all optimized GPS stops.
    @Test func nearestNeighborOrder_noGPSStopAppendedLast() {
        let waypoints = [
            WP(latitude: 0, longitude: 0),  // index 0 – no GPS
            WP(latitude: 1, longitude: 1),  // index 1 – GPS
            WP(latitude: 1, longitude: 3),  // index 2 – GPS
        ]
        let order = RouteOptimizer.nearestNeighborOrder(of: waypoints)
        #expect(order.last == 0)
        #expect(Set(order.dropLast()) == [1, 2])
    }

    // MARK: - haversineKm

    // Boston → New York City ≈ 306 km (accepted range 290–320 km).
    @Test func haversineKm_bostonToNYC_approximatelyCorrect() {
        let boston = WP(latitude: 42.36, longitude: -71.06)
        let nyc    = WP(latitude: 40.71, longitude: -74.01)
        let km = RouteOptimizer.haversineKm(boston, nyc)
        #expect(km > 290 && km < 320)
    }

    @Test func haversineKm_samePoint_isZero() {
        let p = WP(latitude: 37.33, longitude: -122.03)
        #expect(RouteOptimizer.haversineKm(p, p) == 0)
    }
}
