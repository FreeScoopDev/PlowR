import ActivityKit
import Foundation

/// The real Live Activity and home-screen widget behind `ActiveRouteStore`.
/// Moved here from `ActiveRouteView`, which used to own the Activity handle
/// and lose it whenever the view went away.
final class SystemRouteSurfaces: RouteSurfaces {
    private var activity: Activity<PlowRRouteAttributes>?

    func start(_ progress: RouteProgress) {
        writeWidget(progress, isActive: true)
        // One route Live Activity at a time: end any left from an earlier route.
        for stray in Activity<PlowRRouteAttributes>.activities {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
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
        // After a relaunch this route's Activity may still be on the Lock
        // Screen: adopt it rather than start a second. Ended ones (the system
        // ends them after 8 hours but lists them for a while) don't count.
        let all = Activity<PlowRRouteAttributes>.activities
        let candidates = all.map {
            LiveActivityCandidate(id: $0.id, routeID: $0.attributes.routeID,
                                  isRunning: $0.activityState == .active || $0.activityState == .stale)
        }
        let adoptID = LiveActivityCandidate.toAdopt(from: candidates, routeID: progress.routeID.uuidString)
        activity = all.first { $0.id == adoptID }
        for other in all where other.id != adoptID {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
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

    func clear() {
        activity = nil
        for activity in Activity<PlowRRouteAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        // Only a widget still claiming a route is active is stale; a finished
        // route's summary is left for the widget to show.
        if WidgetDataStore.read()?.isActive == true {
            WidgetDataStore.clear()
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

/// A Live Activity as `resume` sees it, so the choice of which one to adopt can
/// be tested without ActivityKit.
nonisolated struct LiveActivityCandidate: Equatable {
    var id: String
    var routeID: String
    var isRunning: Bool

    /// The first still-running activity for `routeID`, or nil.
    static func toAdopt(from candidates: [LiveActivityCandidate], routeID: String) -> String? {
        candidates.first { $0.routeID == routeID && $0.isRunning }?.id
    }
}
