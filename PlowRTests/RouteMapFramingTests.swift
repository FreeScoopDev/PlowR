import CoreLocation
import MapKit
import Testing
@testable import PlowR

struct RouteMapFramingTests {
    private let driver = CLLocationCoordinate2D(latitude: 43.3720, longitude: -72.3500)

    /// About `meters` from the driver, in the direction given in degrees
    /// (0 north, 90 east).
    private func stop(_ meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let r = bearing * .pi / 180
        let north = meters * cos(r) / 111_320
        let east = meters * sin(r) / (111_320 * cos(driver.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: driver.latitude + north, longitude: driver.longitude + east)
    }

    private func contains(_ region: MKCoordinateRegion, _ point: CLLocationCoordinate2D) -> Bool {
        abs(point.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
            && abs(point.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
    }

    /// Points between the stop and the map's top edge, on a map this tall.
    private func roomAbove(_ point: CLLocationCoordinate2D, in region: MKCoordinateRegion, mapHeight: Double = 240) -> Double {
        let top = region.center.latitude + region.span.latitudeDelta / 2
        return (top - point.latitude) / region.span.latitudeDelta * mapHeight
    }

    @Test(arguments: [0.0, 45, 90, 135, 180, 225, 270, 315])
    func driverAndStopBothShow(bearing: Double) {
        let there = stop(4_000, bearing: bearing)
        let region = RouteMapFraming.region(driver: driver, stop: there)
        #expect(contains(region, driver))
        #expect(contains(region, there))
    }

    @Test(arguments: [300.0, 1_000, 3_000, 8_000, 12_000])
    func aStopDueNorthHasRoomForItsPinAndName(meters: Double) {
        let there = stop(meters, bearing: 0)
        let region = RouteMapFraming.region(driver: driver, stop: there)
        // The pin and its name stand about 58 pt above the stop's point.
        #expect(roomAbove(there, in: region) >= 60)
    }

    @Test func aStopNextDoorStillGetsAStreetsWorthOfMap() {
        let there = stop(20, bearing: 90)
        let region = RouteMapFraming.region(driver: driver, stop: there)
        let latitudeMeters = region.span.latitudeDelta * 111_320
        #expect(latitudeMeters >= RouteMapFraming.minimumSpanMeters - 1)
    }

    @Test func aFarStopFramesTheDriverAlone() {
        let there = stop(25_000, bearing: 30)
        let region = RouteMapFraming.region(driver: driver, stop: there)
        #expect(abs(region.center.latitude - driver.latitude) < 1e-9)
        #expect(abs(region.center.longitude - driver.longitude) < 1e-9)
        #expect(!contains(region, there))
        let latitudeMeters = region.span.latitudeDelta * 111_320
        #expect(abs(latitudeMeters - RouteMapFraming.driverOnlyMeters) < 50)
    }
}
