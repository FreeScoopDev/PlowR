import Foundation
import CoreLocation
import MapKit

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// The route screen's GPS: the map's dot, arrival estimates, weather and
    /// the location a text can include. Only while the screen is on screen
    /// with PlowR in front: arrivals and departures are job-site areas
    /// (SiteMonitor), which iOS watches without it. It followed the phone
    /// continuously in the background all route long, which cost crews
    /// battery and wasn't needed (pre-launch review, 2026-10-10).
    static let accuracy = kCLLocationAccuracyNearestTenMeters
    /// Metres moved before a new fix: enough for the map, far less work.
    static let distanceFilter: CLLocationDistance = 20

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = Self.accuracy
        manager.distanceFilter = Self.distanceFilter
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        manager.activityType = .automotiveNavigation
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    func calculateETA(to stop: RouteStop) async -> Int? {
        // A Mac isn't on the route: an estimate from where it is would mislead.
        guard !OnMac.isMac, let currentLocation,
              stop.latitude != 0.0 || stop.longitude != 0.0 else { return nil }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: currentLocation, address: nil)
        request.destination = MKMapItem(
            location: CLLocation(latitude: stop.latitude, longitude: stop.longitude),
            address: nil
        )
        request.transportType = .automobile

        return await withCheckedContinuation { continuation in
            let directions = MKDirections(request: request)
            directions.calculate { response, _ in
                guard let seconds = response?.routes.first?.expectedTravelTime else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: max(1, Int(seconds / 60)))
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
