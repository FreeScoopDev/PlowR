//
//  LocationManagerTests.swift
//  PlowRTests
//

import CoreLocation
import Foundation
import Testing
@testable import PlowR

/// The route screen's GPS runs only with PlowR in front (pre-launch review,
/// 2026-10-10): arrivals and departures are job-site areas, which iOS watches
/// without it.
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
        #expect(manager.distanceFilter == 20)
    }
}
