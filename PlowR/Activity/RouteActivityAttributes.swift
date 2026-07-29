import ActivityKit
import Foundation

struct PlowRRouteAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentStopName: String
        var currentStopAddress: String
        var currentStopNumber: Int
        var totalStops: Int
        var routeName: String
    }

    var routeID: String
    var routeName: String
}
