import WidgetKit
import SwiftUI

@main
struct PlowRWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlowRTodayRouteWidget()
        PlowRWidgetsLiveActivity()
        PlowRWidgetsControl()
    }
}
