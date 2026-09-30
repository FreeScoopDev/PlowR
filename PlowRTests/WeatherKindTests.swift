//
//  WeatherKindTests.swift
//  PlowRTests
//

import SwiftUI
import Testing
@testable import PlowR

/// Every description WeatherService produces is one kind of weather, the same
/// on every screen. The screens used to classify it three ways.
@MainActor
struct WeatherKindTests {
    @Test(arguments: [
        ("Clear", WeatherKind.clear), ("Mostly Clear", .clear),
        ("Partly Cloudy", .cloudy), ("Overcast", .cloudy),
        ("Fog", .fog),
        ("Drizzle", .rain), ("Rain", .rain), ("Showers", .rain),
        ("Freezing Rain", .snow), ("Snow", .snow), ("Snow Grains", .snow), ("Snow Showers", .snow),
        ("Thunderstorm", .thunder),
        ("Something new", .other),
    ])
    func eachDescriptionIsOneKind(description: String, kind: WeatherKind) {
        #expect(WeatherKind(description) == kind)
    }

    // Thunder is purple wherever it shows; it was yellow on the Schedule.
    @Test func thunderIsPurpleAsABackgroundAndAnIcon() {
        #expect(WeatherKind("Thunderstorm").background == .purple)
        #expect(WeatherKind("Thunderstorm").iconColor == .purple)
    }
}
