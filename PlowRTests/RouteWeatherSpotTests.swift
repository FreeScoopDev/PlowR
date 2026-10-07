import CoreLocation
import Testing
@testable import PlowR

struct RouteWeatherSpotTests {
    private func spot(_ stops: [(Double, Double)], at index: Int) -> CLLocationCoordinate2D? {
        RouteWeatherSpot.coordinate(stops: stops.map { (latitude: $0.0, longitude: $0.1) }, currentIndex: index)
    }

    @Test func theCurrentStop() {
        let found = spot([(43.1, -72.1), (43.2, -72.2), (43.3, -72.3)], at: 1)
        #expect(found?.latitude == 43.2 && found?.longitude == -72.2)
    }

    @Test func aStopWithNoPinIsPassedOverForTheNextOne() {
        let found = spot([(43.1, -72.1), (0, 0), (43.3, -72.3)], at: 1)
        #expect(found?.latitude == 43.3)
    }

    @Test func thenTheNearestBehindWhenNothingAheadHasAPin() {
        let found = spot([(43.1, -72.1), (43.2, -72.2), (0, 0), (0, 0)], at: 2)
        #expect(found?.latitude == 43.2)
    }

    @Test func nothingWithoutAPinOrAStop() {
        #expect(spot([(0, 0), (0, 0)], at: 0) == nil)
        #expect(spot([], at: 0) == nil)
        // A route finished, or the index past the end: the last pinned stop.
        #expect(spot([(43.1, -72.1)], at: 5)?.latitude == 43.1)
    }

    @Test func aPinOnTheEquatorOrPrimeMeridianCounts() {
        #expect(spot([(0, -72.1)], at: 0)?.longitude == -72.1)
        #expect(spot([(43.1, 0)], at: 0)?.latitude == 43.1)
    }

    @Test func stopsOnlyWithoutGPS() {
        let statuses: [CLAuthorizationStatus] = [.notDetermined, .authorizedWhenInUse, .authorizedAlways, .denied, .restricted]
        for status in statuses {
            #expect(RouteWeatherSpot.usesStops(isMac: true, status: status), "Mac, \(status.rawValue)")
        }
        #expect(!RouteWeatherSpot.usesStops(isMac: false, status: .notDetermined))
        #expect(!RouteWeatherSpot.usesStops(isMac: false, status: .authorizedWhenInUse))
        #expect(!RouteWeatherSpot.usesStops(isMac: false, status: .authorizedAlways))
        #expect(RouteWeatherSpot.usesStops(isMac: false, status: .denied))
        #expect(RouteWeatherSpot.usesStops(isMac: false, status: .restricted))
    }

    @Test func anImpossibleCoordinateIsSkipped() {
        #expect(spot([(200, -72.1), (43.2, -72.2)], at: 0)?.latitude == 43.2)
    }
}
