import Foundation
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

    // Four stops, where "nearest to the previous stop" and "nearest to the
    // start" give different orders. From A (lon 0): B (lon 1) is nearest; from
    // B, D (lon 2) is nearer than C (lon -1.5). Measuring everything from A
    // instead would pick C before D. The three-stop test above can't tell the
    // two apart. Found by review: the loop's `current` stop was untested.
    @Test func nearestNeighborOrder_measuresFromThePreviousStop() {
        let waypoints = [
            WP(latitude: 1, longitude: 0),     // 0 – start (A)
            WP(latitude: 1, longitude: 1),     // 1 – B
            WP(latitude: 1, longitude: -1.5),  // 2 – C
            WP(latitude: 1, longitude: 2),     // 3 – D
        ]
        #expect(RouteOptimizer.nearestNeighborOrder(of: waypoints) == [0, 1, 3, 2])
    }

    // A crash check: with no stops there is nothing to return, so the
    // expectation can't fail. What it catches is a crash on empty input.
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

    // Fewer than two stops with GPS skips the ordering. The stops without GPS
    // must still come back, after the one with it (found by a test audit).
    @Test func nearestNeighborOrder_oneGPSStop_keepsTheStopsWithout() {
        let waypoints = [
            WP(latitude: 0, longitude: 0),  // index 0 – no GPS
            WP(latitude: 1, longitude: 1),  // index 1 – GPS
            WP(latitude: 0, longitude: 0),  // index 2 – no GPS
        ]
        #expect(RouteOptimizer.nearestNeighborOrder(of: waypoints) == [1, 0, 2])
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

// MARK: - drivingOrder

/// A stand-in for MapKit: answers from a table or a rule, and records every
/// leg it was asked about, in order.
private actor FakeTravelTimes {
    private(set) var asked: [(from: RouteOptimizer.Waypoint, to: RouteOptimizer.Waypoint)] = []
    private let answer: (RouteOptimizer.Waypoint, RouteOptimizer.Waypoint) -> RouteOptimizer.TravelTime

    init(_ answer: @escaping (RouteOptimizer.Waypoint, RouteOptimizer.Waypoint) -> RouteOptimizer.TravelTime) {
        self.answer = answer
    }

    func time(_ from: RouteOptimizer.Waypoint, _ to: RouteOptimizer.Waypoint) -> RouteOptimizer.TravelTime {
        asked.append((from, to))
        return answer(from, to)
    }
}

struct RouteOptimizerDrivingTests {

    private typealias WP = RouteOptimizer.Waypoint

    /// Stops along a line of latitude, `lon` degrees apart.
    private func line(_ lons: [Double]) -> [WP] {
        lons.map { WP(latitude: 45, longitude: $0) }
    }

    /// Driving time equals the straight-line estimate: a "real" answer for every leg.
    private func asTheCrowFlies(_ a: WP, _ b: WP) -> RouteOptimizer.TravelTime {
        .seconds(RouteOptimizer.estimatedSeconds(a, b))
    }

    // Twelve stops: each step asks about at most k (5) remaining stops, so
    // 11 steps ask far fewer than the 66 an every-stop search would. The
    // count per origin is checked directly.
    @Test func asksAboutAtMostKStopsPerStep() async throws {
        let stops = line((0..<12).map { Double($0) * 0.01 })
        let fake = FakeTravelTimes { a, b in .seconds(RouteOptimizer.estimatedSeconds(a, b)) }
        _ = try await RouteOptimizer.drivingOrder(of: stops) { await fake.time($0, $1) }
        let asked = await fake.asked
        let perOrigin = Dictionary(grouping: asked, by: { $0.from.longitude }).mapValues(\.count)
        #expect(perOrigin.values.allSatisfy { $0 <= RouteOptimizer.candidatesPerStep })
        #expect(perOrigin.values.contains(RouteOptimizer.candidatesPerStep))
        #expect(asked.count <= 11 * RouteOptimizer.candidatesPerStep)
    }

    // The k asked about are the nearest by straight line: from the first
    // stop, the five nearest of the rest, never a far one.
    @Test func asksAboutTheNearestStops() async throws {
        let stops = line([0, 0.09, 0.01, 0.08, 0.02, 0.07, 0.03, 0.06, 0.04, 0.05])
        let fake = FakeTravelTimes { a, b in .seconds(RouteOptimizer.estimatedSeconds(a, b)) }
        _ = try await RouteOptimizer.drivingOrder(of: stops) { await fake.time($0, $1) }
        let firstStep = await fake.asked.filter { $0.from.longitude == 0 }.map(\.to.longitude)
        #expect(Set(firstStep) == [0.01, 0.02, 0.03, 0.04, 0.05])
    }

    // One unit: from A, B is nearer by straight line but has no answer (its
    // estimate is used); C is farther but MapKit says it's a 30-second drive.
    // B's estimate (≈ 92 s) is slower, so C wins.
    @Test func estimatedAndRealLegsCompareInSeconds() async throws {
        let a = WP(latitude: 45, longitude: 0)
        let b = WP(latitude: 45, longitude: 0.01)   // ~0.79 km: estimate ≈ 92 s
        let c = WP(latitude: 45, longitude: 0.02)   // real: 30 s
        let result = try await RouteOptimizer.drivingOrder(of: [a, b, c]) { _, to in
            if to.longitude == 0.02 { return .seconds(30) }
            if to.longitude == 0.01 { return .unavailable }
            return .seconds(1_000)
        }
        #expect(result.order == [0, 2, 1])
    }

    // The other side: C's real drive is 110 s, so B's ≈ 92 s estimate wins.
    // The old score (radians × 10⁶, ≈ 123 for B) would have picked C.
    @Test func anEstimatedLegBeatsASlowerRealOne() async throws {
        let a = WP(latitude: 45, longitude: 0)
        let b = WP(latitude: 45, longitude: 0.01)   // ~0.79 km: estimate ≈ 92 s
        let c = WP(latitude: 45, longitude: 0.02)   // real: 110 s
        let result = try await RouteOptimizer.drivingOrder(of: [a, b, c]) { _, to in
            if to.longitude == 0.02 { return .seconds(110) }
            if to.longitude == 0.01 { return .unavailable }
            return .seconds(1_000)
        }
        #expect(result.order == [0, 1, 2])
    }

    @Test func estimateIsInSeconds() {
        let a = WP(latitude: 45, longitude: 0)
        let b = WP(latitude: 45, longitude: 1)
        let km = RouteOptimizer.haversineKm(a, b)
        #expect(abs(RouteOptimizer.estimatedSeconds(a, b) - km * 1.3 / 40 * 3_600) < 0.001)
    }

    // Three unavailable answers in a row: MapKit isn't asked again this run.
    @Test func stopsAskingAfterThreeUnavailableInARow() async throws {
        let stops = line((0..<8).map { Double($0) * 0.01 })
        let fake = FakeTravelTimes { _, _ in .unavailable }
        let result = try await RouteOptimizer.drivingOrder(of: stops) { await fake.time($0, $1) }
        #expect(await fake.asked.count == RouteOptimizer.unavailableCutoff)
        #expect(result.order == Array(0..<8))
    }

    // A real answer between unavailable ones resets the count.
    @Test func aRealAnswerResetsTheUnavailableCount() async throws {
        let stops = line((0..<8).map { Double($0) * 0.01 })
        let fake = FakeTravelTimes { _, to in
            to.longitude == 0.03 ? .seconds(1) : .unavailable
        }
        _ = try await RouteOptimizer.drivingOrder(of: stops) { await fake.time($0, $1) }
        // First step: 0.01 and 0.02 unavailable, 0.03 real (resets), 0.04 and
        // 0.05 unavailable: two in a row, so all five are asked. 0.03 wins; the
        // next step's first unavailable answer is the third in a row. Six in all
        // (without the reset it would stop at 0.04, after four).
        #expect(await fake.asked.count == 6)
    }

    // A throttling answer stops the asking at once.
    @Test func stopsAskingWhenThrottled() async throws {
        let stops = line((0..<8).map { Double($0) * 0.01 })
        let fake = FakeTravelTimes { _, _ in .throttled }
        let result = try await RouteOptimizer.drivingOrder(of: stops) { await fake.time($0, $1) }
        #expect(await fake.asked.count == 1)
        #expect(result.estimatedLegs == 7)
    }

    // Stops without GPS come last, in their own order; the first stop with GPS stays first.
    @Test func keepsTheFirstStopAndAppendsStopsWithoutGPS() async throws {
        let stops = [
            WP(latitude: 0, longitude: 0),      // 0 – no GPS
            WP(latitude: 45, longitude: 0.05),  // 1 – first with GPS
            WP(latitude: 45, longitude: 0.01),  // 2
            WP(latitude: 0, longitude: 0),      // 3 – no GPS
            WP(latitude: 45, longitude: 0.04),  // 4
        ]
        let result = try await RouteOptimizer.drivingOrder(of: stops) { asTheCrowFlies($0, $1) }
        #expect(result.order == [1, 4, 2, 0, 3])
    }

    @Test func firstStopStaysFirstEvenIfNotAnEnd() async throws {
        let stops = line([0.02, 0, 0.05])
        let result = try await RouteOptimizer.drivingOrder(of: stops) { asTheCrowFlies($0, $1) }
        #expect(result.order.first == 0)
        #expect(result.order == [0, 1, 2])
    }

    // N of M: legs are counted between stops with GPS, and only chosen legs
    // that were estimated count.
    @Test func countsEstimatedLegs() async throws {
        let stops = line([0, 0.01, 0.02, 0.03]) + [WP(latitude: 0, longitude: 0)]
        // Only legs into 0.02 have no answer.
        let result = try await RouteOptimizer.drivingOrder(of: stops) { a, b in
            b.longitude == 0.02 ? .unavailable : .seconds(RouteOptimizer.estimatedSeconds(a, b))
        }
        #expect(result.order == [0, 1, 2, 3, 4])
        #expect(result.legs == 3)
        #expect(result.estimatedLegs == 1)
    }

    @Test func noEstimatedLegsWhenEveryAnswerIsReal() async throws {
        let stops = line([0, 0.03, 0.01, 0.02])
        let result = try await RouteOptimizer.drivingOrder(of: stops) { asTheCrowFlies($0, $1) }
        #expect(result.estimatedLegs == 0)
        #expect(result.legs == 3)
    }

    // Cancelled during the first answer: the run throws (no order) and
    // asks nothing more. The first step has five candidates, so a run that
    // only checked at the top of each step would ask four more first.
    @Test func cancelledRunThrowsWithoutAskingAgain() async {
        let stops = line((0..<6).map { Double($0) * 0.01 })
        let fake = FakeTravelTimes { a, b in .seconds(RouteOptimizer.estimatedSeconds(a, b)) }
        let task = Task {
            try await RouteOptimizer.drivingOrder(of: stops) { a, b in
                let answer = await fake.time(a, b)
                withUnsafeCurrentTask { $0?.cancel() }
                return answer
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await fake.asked.count == 1)
    }

    @Test func fewerThanTwoGPSStopsAsksNothing() async throws {
        let fake = FakeTravelTimes { _, _ in .seconds(1) }
        let result = try await RouteOptimizer.drivingOrder(
            of: [WP(latitude: 0, longitude: 0), WP(latitude: 45, longitude: 1)]) { await fake.time($0, $1) }
        #expect(result.order == [1, 0])
        #expect(await fake.asked.isEmpty)
    }

    // MARK: - estimateNote

    @Test func noNoteWhenNoLegWasEstimated() {
        #expect(RouteOptimizer.estimateNote(estimatedLegs: 0, legs: 4) == nil)
    }

    @Test func noteForSomeEstimatedLegs() {
        #expect(RouteOptimizer.estimateNote(estimatedLegs: 2, legs: 5)
            == "Some drive times weren't available, so 2 of 5 legs used straight-line distance.")
    }

    @Test func noteForOneEstimatedLeg() {
        #expect(RouteOptimizer.estimateNote(estimatedLegs: 1, legs: 5)
            == "A drive time wasn't available, so 1 of 5 legs used straight-line distance.")
    }

    @Test func noteWhenEveryLegWasEstimated() {
        let all = "Drive times weren't available, so the order uses straight-line distance."
        #expect(RouteOptimizer.estimateNote(estimatedLegs: 4, legs: 4) == all)
        #expect(RouteOptimizer.estimateNote(estimatedLegs: 1, legs: 1) == all)
    }
}

// MARK: - stopSnapshot

struct RouteOptimizerSnapshotTests {

    private typealias Place = RouteOptimizer.StopPlace

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func snapshot(_ stops: [(UUID, Place)]) -> [UUID: Place] {
        RouteOptimizer.stopSnapshot(stops.map { (id: $0.0, place: $0.1) })
    }

    private var start: [(UUID, Place)] {
        [(a, Place(order: 0, latitude: 45, longitude: 1)),
         (b, Place(order: 1, latitude: 45, longitude: 2))]
    }

    // Same stops, listed in another sequence (stops sharing an order can
    // sort either way): still equal.
    @Test func unchangedStopsAreEqualInAnySequence() {
        #expect(snapshot(start) == snapshot(start))
        #expect(snapshot(start) == snapshot(start.reversed()))
    }

    @Test func oneOrderChangedIsNotEqual() {
        var after = start
        after[1].1 = Place(order: 2, latitude: 45, longitude: 2)
        #expect(snapshot(start) != snapshot(after))
    }

    @Test func oneCoordinateChangedIsNotEqual() {
        var after = start
        after[0].1 = Place(order: 0, latitude: 45, longitude: 1.5)
        #expect(snapshot(start) != snapshot(after))
    }

    @Test func aStopAddedOrRemovedIsNotEqual() {
        let added = start + [(c, Place(order: 2, latitude: 45, longitude: 3))]
        #expect(snapshot(start) != snapshot(added))
        #expect(snapshot(start) != snapshot(Array(start.dropLast())))
    }
}
