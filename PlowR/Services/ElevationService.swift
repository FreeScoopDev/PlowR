import Foundation
import CoreLocation

actor ElevationService {
    static let shared = ElevationService()

    private struct Response: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let elevation: Double
        }
    }

    // Returns percent grade (0 = flat, 5 = moderate, 15+ = steep) for a polygon.
    // Samples the first and last points as a proxy for the zone's slope axis.
    func fetchGrade(for coordinates: [CLLocationCoordinate2D]) async -> Double {
        guard coordinates.count >= 2 else { return 0 }

        // Sample start, midpoint, and end to cover the zone's slope
        let indices = [0, coordinates.count / 2, coordinates.count - 1]
        let samples = indices.map { coordinates[$0] }
        let locationString = samples.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")

        guard let url = URL(string: "https://api.open-topo-data.com/v1/srtm30m?locations=\(locationString)") else {
            return 0
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            let elevations = response.results.map { $0.elevation }
            guard let minE = elevations.min(), let maxE = elevations.max(), maxE > minE else { return 0 }

            // Calculate horizontal distance between first and last sample
            let start = CLLocation(latitude: samples.first!.latitude, longitude: samples.first!.longitude)
            let end = CLLocation(latitude: samples.last!.latitude, longitude: samples.last!.longitude)
            let distance = start.distance(from: end)
            guard distance > 0 else { return 0 }

            return ((maxE - minE) / distance) * 100
        } catch {
            return 0
        }
    }
}
