import Foundation
import WidgetKit

/// Data written by the main app into the shared App Group container
/// and read by the PlowRWidgets extension to power the Today's Route widget.
struct TodayRouteWidgetData: Codable {
    var routeName: String = ""
    var totalStops: Int = 0
    var completedStops: Int = 0
    var nextStopName: String = ""
    var nextStopAddress: String = ""
    var isActive: Bool = false
    var lastUpdated: Date = .distantPast
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
