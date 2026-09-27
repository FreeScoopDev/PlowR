import CoreLocation
import MapKit

/// The smallest latitude/longitude box that contains a set of points.
///
/// The initializer is failable because an empty set has no bounds. That makes
/// the empty case impossible to forget: the route map, the route recap map and
/// the proposal PDF's minimap each used to compute min/max by hand and
/// force-unwrap it, relying on a separate emptiness check a few lines up.
///
/// `nonisolated` because the app target defaults to @MainActor and this is
/// plain arithmetic, used from views and from PDF drawing alike.
nonisolated struct CoordinateBounds: Equatable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    init?(latitudes: [Double], longitudes: [Double]) {
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return nil }
        minLatitude = minLat
        maxLatitude = maxLat
        minLongitude = minLon
        maxLongitude = maxLon
    }

    init?(_ coordinates: [CLLocationCoordinate2D]) {
        self.init(latitudes: coordinates.map(\.latitude), longitudes: coordinates.map(\.longitude))
    }

    var latitudeSpan: Double { maxLatitude - minLatitude }
    var longitudeSpan: Double { maxLongitude - minLongitude }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2,
                               longitude: (minLongitude + maxLongitude) / 2)
    }

    /// A map region showing the whole box with some margin. `padding` scales the
    /// span (1.7 leaves room for pins at the edges); `minimumDelta` stops two
    /// stops on the same street from zooming in to rooftop level.
    func region(padding: Double = 1.7, minimumDelta: Double = 0.006) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: max(latitudeSpan * padding, minimumDelta),
                                   longitudeDelta: max(longitudeSpan * padding, minimumDelta))
        )
    }
}
func brokenOnPurpose() -> Int { [1, 2].first! }  // BROKEN ON PURPOSE, reverted next commit
