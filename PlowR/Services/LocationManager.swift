import Foundation
import CoreLocation
import MapKit
import SwiftUI

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// The route screen's GPS: the map's dot, arrival estimates, weather and
    /// the location a text can include. Only while the screen is on screen
    /// with PlowR in front: arrivals and departures are job-site areas
    /// (SiteMonitor), which iOS watches without it when Location is set to
    /// Always (on While Using, only on screen: RouteGPS.needsAlways). It followed the phone
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

    /// Stops, and forgets the last fix: once PlowR is away it goes stale, and
    /// an arrival estimate or a text's location from where the phone was
    /// minutes ago would be wrong. The next fix comes within a second or two
    /// of coming back.
    func stopTracking() {
        manager.stopUpdatingLocation()
        currentLocation = nil
    }

    /// Asks iOS for Always once a route runs on While Using: arrivals and
    /// departures (SiteMonitor) reach PlowR in the background only with
    /// Always. iOS shows this once; after that only Settings can change it.
    func requestAlways() {
        manager.requestAlwaysAuthorization()
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
        // The first fix after GPS restarts can be one iOS kept from minutes
        // ago (where the phone was locked): skipped, so the estimate and a
        // text's location wait for a fresh one.
        guard let fix = locations.last(where: { RouteGPS.isFresh($0) }) else { return }
        currentLocation = fix
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

/// What the route screen does with GPS as the app comes and goes. Kept out of
/// the view so it can be tested.
enum RouteGPS {
    enum Action: Equatable { case start, stop, none }

    /// On screen: on, if allowed and not a Mac. Away: off. In between (Control
    /// Center pulled down, a call): as it was.
    static func action(for phase: ScenePhase, isMac: Bool, status: CLAuthorizationStatus) -> Action {
        switch phase {
        case .active:
            return !isMac && (status == .authorizedAlways || status == .authorizedWhenInUse) ? .start : .none
        case .background:
            return .stop
        default:
            return .none
        }
    }

    /// Arrival and departure times need Always: on While Using, iOS hands
    /// PlowR a job-site crossing only while it's on screen. The route screen
    /// says so (not on a Mac, which follows no route).
    /// A fix worth using: a real position from the last few seconds.
    static func isFresh(_ fix: CLLocation, now: Date = .now) -> Bool {
        fix.horizontalAccuracy >= 0 && now.timeIntervalSince(fix.timestamp) <= 10
    }

    static func needsAlways(status: CLAuthorizationStatus, isMac: Bool) -> Bool {
        !isMac && status == .authorizedWhenInUse
    }
}
