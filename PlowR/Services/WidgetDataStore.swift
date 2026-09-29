import Foundation
import WidgetKit

/// Today's route as the home-screen widget shows it: written by the app into
/// the shared app group, read by the PlowRWidgets extension. This file is
/// compiled into both targets, so they can't disagree about the fields. The
/// widget used to declare its own copy, and renaming a field here would have
/// turned it into "No Active Route" with nothing to catch it.
///
/// `nonisolated`: plain values, read by the widget's timeline provider.
nonisolated struct TodayRouteWidgetData: Codable, Equatable {
    var routeName: String = ""
    var totalStops: Int = 0
    var completedStops: Int = 0
    var nextStopName: String = ""
    var nextStopAddress: String = ""
    var isActive: Bool = false
    var lastUpdated: Date = .distantPast

    var hasData: Bool { totalStops > 0 }
    /// The route was ended with every stop done.
    var isComplete: Bool { !isActive && completedStops == totalStops && totalStops > 0 }
    var progress: Double { totalStops > 0 ? min(1, Double(completedStops) / Double(totalStops)) : 0 }

    /// "Stop 4 of 8", or once every stop is done, "All 8 stops done". After the
    /// last stop it read "Stop 9 of 8" until the route was ended.
    var stopLine: String {
        if totalStops == 0 { return "No stops" }
        if completedStops >= totalStops { return "All \(totalStops) stops done" }
        return "Stop \(completedStops + 1) of \(totalStops)"
    }
}

enum WidgetDataStore {
    private static let suiteName = "group.com.Scoops.PlowR"
    private static let key = "todayRoute"

    static func write(_ data: TodayRouteWidgetData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults(suiteName: suiteName)?.set(encoded, forKey: key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "PlowRTodayRoute")
    }

    static func read() -> TodayRouteWidgetData? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TodayRouteWidgetData.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: "PlowRTodayRoute")
    }
}
