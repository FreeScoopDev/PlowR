import Foundation
import SwiftData
import CoreLocation

@Model
final class PropertyZone {
    var id: UUID = UUID()
    var label: String = ""
    var areaSquareFeet: Double = 0.0
    var rateType: String = "perSqFt"    // "flat" or "perSqFt"
    var coordinatesData: Data = Data()  // JSON-encoded [[lat, lon]]
    var elevationGrade: Double = 0.0    // percent grade (rise/run × 100)
    var sortOrder: Int = 0
    var client: Client?

    init(label: String, rateType: String = "perSqFt", sortOrder: Int = 0) {
        self.label = label
        self.rateType = rateType
        self.sortOrder = sortOrder
    }
}

extension PropertyZone {
    var coordinates: [CLLocationCoordinate2D] {
        guard let decoded = try? JSONDecoder().decode([[Double]].self, from: coordinatesData) else { return [] }
        return decoded.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    func setCoordinates(_ coords: [CLLocationCoordinate2D]) {
        let pairs = coords.map { [$0.latitude, $0.longitude] }
        coordinatesData = (try? JSONEncoder().encode(pairs)) ?? Data()
    }

    var terrainLabel: String {
        switch elevationGrade {
        case ..<2:   return "Flat"
        case 2..<8:  return "Moderate Slope"
        default:     return "Steep"
        }
    }
}

extension Array where Element == CLLocationCoordinate2D {
    func enclosedAreaInSquareFeet() -> Double {
        guard count >= 3 else { return 0 }
        let earthRadius = 6_371_000.0
        let centerLat = reduce(0) { $0 + $1.latitude } / Double(count)
        let latRad = centerLat * .pi / 180
        let mPerDegLat = earthRadius * .pi / 180
        let mPerDegLon = mPerDegLat * cos(latRad)
        var area = 0.0
        for i in 0..<count {
            let j = (i + 1) % count
            let xi = self[i].longitude * mPerDegLon
            let yi = self[i].latitude * mPerDegLat
            let xj = self[j].longitude * mPerDegLon
            let yj = self[j].latitude * mPerDegLat
            area += xi * yj - xj * yi
        }
        return abs(area / 2) * 10.7639 // m² → sq ft
    }
}
