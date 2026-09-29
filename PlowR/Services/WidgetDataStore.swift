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
    /// The stop the widget shows. Optional, so data an older version wrote
    /// still reads.
    var currentStopID: UUID?

    /// The stop Control Center's Complete Stop completes: the one shown,
    /// while a route is in progress. None once every stop is done.
    var shownStopID: UUID? { isActive ? currentStopID : nil }

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
    static let suiteName = "group.com.Scoops.PlowR"
    static let key = "todayRoute"
    /// The widget's kind. The widget declares itself with it and the app
    /// reloads it by it, so the two can't drift apart.
    static let widgetKind = "PlowRTodayRoute"

    static func write(_ data: TodayRouteWidgetData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults(suiteName: suiteName)?.set(encoded, forKey: key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func read() -> TodayRouteWidgetData? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TodayRouteWidgetData.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
