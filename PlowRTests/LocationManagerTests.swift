//
//  LocationManagerTests.swift
//  PlowRTests
//

import CoreLocation
import Foundation
import SwiftUI
import Testing
@testable import PlowR

/// The route screen's GPS runs only with PlowR in front (pre-launch review,
/// 2026-10-10): arrivals and departures are job-site areas, which iOS watches
/// without it when Location is set to Always.
@MainActor
struct LocationManagerTests {

    // No background location mode: App Review asks every app that has one
    // why, and nothing in PlowR needs it. A manager told to keep updating in
    // the background without the mode would stop the app.
    @Test func theAppHasNoBackgroundLocationMode() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        #expect(!modes.contains("location"))
    }

    @Test func trackingStaysInTheForegroundAndCoarse() {
        let manager = CLLocationManager()
        let location = LocationManager(manager: manager)
        location.startTracking()
        defer { location.stopTracking() }
        #expect(!manager.allowsBackgroundLocationUpdates)
        #expect(manager.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)
        #expect(manager.distanceFilter == kCLDistanceFilterNone)         // until a fresh fix
        location.locationManager(manager, didUpdateLocations: [CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 43.37, longitude: -72.34), altitude: 0,
            horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date())])
        #expect(manager.distanceFilter == 20)
    }

    @Test func trackingIsForDriving() {
        let manager = CLLocationManager()
        let location = LocationManager(manager: manager)
        location.startTracking()
        defer { location.stopTracking() }
        #expect(manager.activityType == .automotiveNavigation)
    }

    // Away, the last fix goes stale: an estimate or a text's location from
    // where the phone was minutes ago would be wrong.
    @Test func stoppingForgetsTheLastFix() {
        let location = LocationManager(manager: CLLocationManager())
        location.currentLocation = CLLocation(latitude: 43.37, longitude: -72.34)
        location.stopTracking()
        #expect(location.currentLocation == nil)
    }

    @Test func gpsRunsOnlyOnScreen() {
        typealias GPS = RouteGPS
        #expect(GPS.action(for: .active, isMac: false, status: .authorizedAlways) == .start)
        #expect(GPS.action(for: .active, isMac: false, status: .authorizedWhenInUse) == .start)
        #expect(GPS.action(for: .active, isMac: false, status: .denied) == .none)
        #expect(GPS.action(for: .active, isMac: false, status: .notDetermined) == .none)
        #expect(GPS.action(for: .active, isMac: true, status: .authorizedAlways) == .none)
        #expect(GPS.action(for: .background, isMac: false, status: .authorizedAlways) == .stop)
        #expect(GPS.action(for: .inactive, isMac: false, status: .authorizedAlways) == .none)
    }

    // On While Using, job-site crossings reach PlowR only while it's on
    // screen: the route screen says Always is needed.
    @Test func arrivalTimesNeedAlways() {
        #expect(RouteGPS.needsAlways(status: .authorizedWhenInUse, isMac: false))
        #expect(!RouteGPS.needsAlways(status: .authorizedAlways, isMac: false))
        #expect(!RouteGPS.needsAlways(status: .denied, isMac: false))
        #expect(!RouteGPS.needsAlways(status: .authorizedWhenInUse, isMac: true))
    }

    // The first fix after GPS restarts can be minutes old (where the phone
    // was locked): an estimate or a text's location waits for a fresh one.
    @Test func anOldFixIsntUsed() {
        let location = LocationManager(manager: CLLocationManager())
        let here = CLLocationCoordinate2D(latitude: 43.37, longitude: -72.34)
        func fix(ago seconds: TimeInterval, accuracy: Double = 10) -> CLLocation {
            CLLocation(coordinate: here, altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10,
                       timestamp: Date().addingTimeInterval(-seconds))
        }
        location.locationManager(CLLocationManager(), didUpdateLocations: [fix(ago: 300)])
        #expect(location.currentLocation == nil)
        location.locationManager(CLLocationManager(), didUpdateLocations: [fix(ago: 0, accuracy: -1)])
        #expect(location.currentLocation == nil)
        location.locationManager(CLLocationManager(), didUpdateLocations: [fix(ago: 300), fix(ago: 1)])
        #expect(location.currentLocation != nil)
        // The newest fresh one of a batch.
        let newest = fix(ago: 1)
        location.locationManager(CLLocationManager(), didUpdateLocations: [fix(ago: 5), newest])
        #expect(location.currentLocation?.timestamp == newest.timestamp)
    }
}

