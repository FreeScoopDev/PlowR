import ActivityKit
import Foundation

/// The real Live Activity and home-screen widget behind `ActiveRouteStore`.
/// Moved here from `ActiveRouteView`, which used to own the Activity handle
/// and lose it whenever the view went away.
final class SystemRouteSurfaces: RouteSurfaces {
    private var activity: Activity<PlowRRouteAttributes>?

    func start(_ progress: RouteProgress) {
        writeWidget(progress, isActive: true)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity<PlowRRouteAttributes>.request(
            attributes: PlowRRouteAttributes(routeID: progress.routeID.uuidString, routeName: progress.routeName),
            content: .init(state: state(progress), staleDate: nil)
        )
    }

    func update(_ progress: RouteProgress) {
        writeWidget(progress, isActive: true)
        guard let activity else { return }
        let content = ActivityContent(state: state(progress), staleDate: nil)
        Task { await activity.update(content) }
    }

    func resume(_ progress: RouteProgress) {
        // After a relaunch the Activity may still be on the Lock Screen: adopt
        // it rather than starting a second one. If it's gone, start a new one.
        activity = Activity<PlowRRouteAttributes>.activities
            .first { $0.attributes.routeID == progress.routeID.uuidString }
        if activity == nil {
            start(progress)
        } else {
            update(progress)
        }
    }

    func end(_ progress: RouteProgress) {
        writeWidget(progress, isActive: false)
        var final = progress
        final.currentStopName = "Route Complete"
        final.currentStopAddress = ""
        final.currentStopNumber = progress.totalStops
        let content = ActivityContent(state: state(final), staleDate: nil)
        let ending = activity.map { [$0] } ?? Activity<PlowRRouteAttributes>.activities
            .filter { $0.attributes.routeID == progress.routeID.uuidString }
        activity = nil
        for activity in ending {
            Task { await activity.end(content, dismissalPolicy: .after(.now + 30)) }
        }
    }

    func endStray(keeping routeID: UUID?) {
        for activity in Activity<PlowRRouteAttributes>.activities
        where activity.attributes.routeID != routeID?.uuidString {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func state(_ p: RouteProgress) -> PlowRRouteAttributes.ContentState {
        PlowRRouteAttributes.ContentState(
            currentStopName: p.currentStopName,
            currentStopAddress: p.currentStopAddress,
            currentStopNumber: p.currentStopNumber,
            totalStops: p.totalStops,
            routeName: p.routeName
        )
    }

    private func writeWidget(_ p: RouteProgress, isActive: Bool) {
        WidgetDataStore.write(TodayRouteWidgetData(
            routeName: p.routeName,
            totalStops: p.totalStops,
            completedStops: isActive ? p.completedStops : p.totalStops,
            nextStopName: isActive ? p.currentStopName : "",
            nextStopAddress: isActive ? p.currentStopAddress : "",
            isActive: isActive,
            lastUpdated: Date()
        ))
    }
}
