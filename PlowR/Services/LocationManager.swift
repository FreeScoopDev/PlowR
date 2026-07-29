import Foundation
import CoreLocation
import MapKit

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var lastExitedRegionID: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        clearAllGeofences()
    }

    func startMonitoringStop(_ stop: RouteStop) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        guard stop.latitude != 0.0 || stop.longitude != 0.0 else { return }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
            radius: 100,
            identifier: stop.id.uuidString
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false
        manager.startMonitoring(for: region)
    }

    func clearAllGeofences() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    func calculateETA(to stop: RouteStop) async -> Int? {
        guard let currentLocation,
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

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        DispatchQueue.main.async { [weak self] in
            self?.lastExitedRegionID = region.identifier
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Geofencing failure is non-fatal; the operator can manually advance stops
    }
}
