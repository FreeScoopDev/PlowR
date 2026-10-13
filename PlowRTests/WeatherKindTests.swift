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

    // Thunder has one colour wherever it shows; it was yellow on the
    // Schedule. The icon is the lead token (the design's purple, 1.7).
    @Test func thunderUsesTheLeadColourAsAnIcon() {
        // A Color made from a dynamic UIColor isn't equal to another made the
        // same way: compare what each draws, in light and dark.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            #expect(UIColor(WeatherKind("Thunderstorm").iconColor).resolvedColor(with: traits)
                    == PlowRColor.Status.lead.fillUIColor.resolvedColor(with: traits))
        }
    }
}
