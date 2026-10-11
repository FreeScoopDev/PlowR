import CoreLocation
import MapKit

/// What the route screen's map shows while following the driver: the driver
/// and the stop they're heading to, with room above the stop for its pin and
/// name. A camera height (the old way) left the stop's pin on the top edge of
/// the wide, short map; a region is fitted inside the map whatever its shape.
nonisolated enum RouteMapFraming {
    /// How far apart driver and stop can be and still both show legibly.
    /// Further, the map frames the driver alone (`driverOnlyMeters`): the
    /// first stop of a morning can be 30 km from the yard, and a map that
    /// wide is empty road with two dots.
    static let farthestFramedMeters: CLLocationDistance = 12_000
    static let driverOnlyMeters: CLLocationDistance = 3_000

    /// North–south: the stop's pin stands about 58 pt above its point on a
    /// 240 pt map, so a stop due north needs about a quarter of the map
    /// above it. With the pair centred, a span of 2.4 × their distance
    /// leaves 240 × (0.5 − 0.5 / 2.4) = 70 pt.
    static let northSouthFactor = 2.4
    /// East–west: the stop's name is centred on its point, so a stop due
    /// east or west needs half a long name's width (about 60 pt) beside it
    /// on a map about 330 pt wide: 330 × (0.5 − 0.5 / 1.8) ≈ 73 pt.
    static let eastWestFactor = 1.8
    /// Room around a stop next door to the driver, so the pins don't touch.
    static let minimumSpanMeters: CLLocationDistance = 400

    static func region(driver: CLLocationCoordinate2D,
                       stop: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let stopLocation = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
        let distance = CLLocation(latitude: driver.latitude, longitude: driver.longitude)
            .distance(from: stopLocation)
        guard distance <= farthestFramedMeters else {
            return MKCoordinateRegion(center: driver,
                                      latitudinalMeters: driverOnlyMeters,
                                      longitudinalMeters: driverOnlyMeters)
        }
        let northSouth = CLLocation(latitude: driver.latitude, longitude: stop.longitude)
            .distance(from: stopLocation)
        let eastWest = CLLocation(latitude: stop.latitude, longitude: driver.longitude)
            .distance(from: stopLocation)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (driver.latitude + stop.latitude) / 2,
                                           longitude: (driver.longitude + stop.longitude) / 2),
            latitudinalMeters: max(northSouth * northSouthFactor, minimumSpanMeters),
            longitudinalMeters: max(eastWest * eastWestFactor, minimumSpanMeters)
        )
    }
}
