import Foundation
import CoreLocation

/// Terrain grade for property zones, from Open Topo Data's free, keyless public
/// API (SRTM 30 m data). Only coordinates are sent: no identity.
///
/// The host was `api.open-topo-data.com`, which does not exist, so every lookup
/// failed silently and every zone read as flat.
///
/// The public API allows 100 locations per request and one request per second,
/// so all of a property's zones go in one request (three sample points each),
/// and every request waits its turn, across calls as well as within one.
actor ElevationService {
    static let shared = ElevationService()

    nonisolated static let host = "api.opentopodata.org"
    nonisolated static let maxLocationsPerRequest = 100
    nonisolated static let samplesPerZone = 3
    /// A little over the API's one request per second.
    nonisolated static let defaultPause: Duration = .seconds(1.1)

    typealias Fetch = @Sendable (URL) async throws -> (Data, URLResponse)
    private let fetch: Fetch
    private let pause: Duration
    /// When the latest request went, or is booked to go.
    private var lastRequest: ContinuousClock.Instant?

    /// `fetch` and `pause` exist for tests; the app uses the defaults.
    init(fetch: @escaping Fetch = { try await URLSession.shared.data(from: $0) },
         pause: Duration = ElevationService.defaultPause) {
        self.fetch = fetch
        self.pause = pause
    }

    private nonisolated struct Response: Decodable {
        let results: [Result]
        struct Result: Decodable {
            // null where the dataset has no data (e.g. open water).
            let elevation: Double?
        }
    }

    /// Percent grade for each zone, in order (0 = flat). nil where the grade
    /// couldn't be looked up (offline, rate-limited, no data), so a caller can
    /// keep a value it already has rather than resetting it to flat.
    func fetchGrades(for zones: [[CLLocationCoordinate2D]]) async -> [Double?] {
        let samples = zones.map(Self.samplePoints)
        let zonesPerRequest = Self.maxLocationsPerRequest / Self.samplesPerZone
        var grades: [Double?] = Array(repeating: nil, count: zones.count)
        var start = 0
        while start < zones.count {
            let end = min(start + zonesPerRequest, zones.count)
            let batch = Array(samples[start..<end])
            if let elevations = await elevations(for: batch.flatMap { $0 }) {
                var offset = 0
                for (i, points) in batch.enumerated() {
                    let slice = Array(elevations[offset..<(offset + points.count)])
                    grades[start + i] = points.isEmpty ? 0 : Self.grade(samples: points, elevations: slice)
                    offset += points.count
                }
            }
            start = end
        }
        return grades
    }

    /// One zone's grade, or nil if it couldn't be looked up.
    func fetchGrade(for coordinates: [CLLocationCoordinate2D]) async -> Double? {
        await fetchGrades(for: [coordinates]).first ?? nil
    }

    private func elevations(for points: [CLLocationCoordinate2D]) async -> [Double?]? {
        guard !points.isEmpty else { return [] }
        guard let url = Self.requestURL(for: points) else { return nil }
        await waitForTurn()
        guard let (data, response) = try? await fetch(url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              decoded.results.count == points.count else { return nil }
        return decoded.results.map(\.elevation)
    }

    /// Books the next free slot, at least `pause` after the previous request,
    /// and waits for it. The slot is booked before waiting, so a call that
    /// arrives meanwhile queues behind it instead of going at the same moment.
    private func waitForTurn() async {
        let clock = ContinuousClock()
        let now = clock.now
        let slot = lastRequest.map { max(now, $0.advanced(by: pause)) } ?? now
        lastRequest = slot
        if slot > now { try? await clock.sleep(until: slot) }
    }

    // MARK: - Pure parts, tested

    /// A zone's start, middle and end corners, used as a proxy for its slope.
    nonisolated static func samplePoints(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return [] }
        return [0, coordinates.count / 2, coordinates.count - 1].map { coordinates[$0] }
    }

    /// Coordinates go out rounded to five decimals, about a metre: the 30 m
    /// dataset gains nothing from more.
    nonisolated static func requestURL(for points: [CLLocationCoordinate2D]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1/srtm30m"
        components.queryItems = [URLQueryItem(
            name: "locations",
            value: points.map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }.joined(separator: "|")
        )]
        return components.url
    }

    /// Rise over run, as a percentage: the spread between the highest and lowest
    /// known sample, over the distance from the first sample to the last.
    nonisolated static func grade(samples: [CLLocationCoordinate2D], elevations: [Double?]) -> Double? {
        let known = elevations.compactMap { $0 }
        guard known.count >= 2 else { return nil }
        guard let minE = known.min(), let maxE = known.max(), maxE > minE,
              let first = samples.first, let last = samples.last else { return 0 }
        let distance = CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
        guard distance > 0 else { return 0 }
        return (maxE - minE) / distance * 100
    }
}
