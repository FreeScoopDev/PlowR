import Foundation
import SwiftData

/// The one place an in-progress route lives.
///
/// Before this existed, the current stop, the stop timer and the Live Activity
/// were `@State` inside `ActiveRouteView`, and the view's `onDisappear` ended
/// the route. Killing the app lost the route's progress, and anything that
/// wasn't that view on screen (Siri, Control Center) had nothing to act on.
///
/// Now the store owns the route and saves a small checkpoint on every change,
/// so a relaunch comes back at the same stop. Views, intents and the Live
/// Activity all go through it. Only `start(_:)` and `end()` begin and finish a
/// route; no view lifecycle event does.
@Observable
final class ActiveRouteStore {
    static let shared = ActiveRouteStore()

    /// What survives the app being killed. Deliberately tiny: the route and
    /// its stops are already in SwiftData, so only the position is saved.
    struct Checkpoint: Codable, Equatable {
        var routeID: UUID
        var currentStopIndex: Int
        var stopStartedAt: Date
    }

    /// What completing the current stop did, so callers (the screen, Siri,
    /// Control Center) can say what actually happened.
    enum CompletionResult: Equatable {
        case advanced(nextStopIndex: Int)
        case finishedLastStop
        case noActiveRoute
        case allStopsAlreadyDone
    }

    private(set) var route: PlowRoute?
    private(set) var currentStopIndex = 0
    private(set) var stopStartedAt: Date?

    /// True from `start(_:)` until the screen has offered to notify the first
    /// client. A route restored after a relaunch does not offer it again.
    var isFirstStopPromptPending = false

    private var context: ModelContext?
    private let defaults: UserDefaults
    private let surfaces: RouteSurfaces
    private let now: () -> Date
    static let checkpointKey = "activeRouteCheckpoint"

    init(defaults: UserDefaults = .standard,
         surfaces: RouteSurfaces = SystemRouteSurfaces(),
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.surfaces = surfaces
        self.now = now
    }

    // MARK: - Derived

    var isActive: Bool { route != nil }
    var sortedStops: [RouteStop] { route?.sortedStops ?? [] }

    var currentStop: RouteStop? {
        sortedStops.indices.contains(currentStopIndex) ? sortedStops[currentStopIndex] : nil
    }

    var nextStop: RouteStop? {
        sortedStops.indices.contains(currentStopIndex + 1) ? sortedStops[currentStopIndex + 1] : nil
    }

    var isLastStop: Bool { currentStopIndex == sortedStops.count - 1 }
    var allStopsDone: Bool { isActive && currentStopIndex >= sortedStops.count }

    // MARK: - Lifecycle

    /// Gives the store its SwiftData context and brings back a route that was
    /// in progress when the app last stopped. Call once, at launch.
    func configure(context: ModelContext) {
        self.context = context
        restore()
    }

    /// Begins `route` at its first stop. Replaces any route already active.
    func start(_ route: PlowRoute) {
        if isActive { end() }
        self.route = route
        currentStopIndex = 0
        stopStartedAt = now()
        isFirstStopPromptPending = true
        saveCheckpoint()
        surfaces.start(progress)
    }

    /// Records the current stop's visit on its client and moves to the next
    /// stop. On the last stop, moves past it: the route is then "all stops
    /// done" and waits for `end()`, so the recap can still be reviewed.
    @discardableResult
    func completeCurrentStop() -> CompletionResult {
        guard isActive else { return .noActiveRoute }
        guard let stop = currentStop else { return .allStopsAlreadyDone }
        recordVisit(for: stop)
        currentStopIndex += 1
        stopStartedAt = now()
        saveCheckpoint()
        surfaces.update(progress)
        return currentStop == nil ? .finishedLastStop : .advanced(nextStopIndex: currentStopIndex)
    }

    /// Finishes the route: clears the checkpoint and ends the Live Activity.
    func end() {
        guard isActive else { return }
        surfaces.end(progress)
        route = nil
        currentStopIndex = 0
        stopStartedAt = nil
        isFirstStopPromptPending = false
        defaults.removeObject(forKey: Self.checkpointKey)
    }

    // MARK: - Progress for the Live Activity and widget

    var progress: RouteProgress {
        RouteProgress(
            routeID: route?.id ?? UUID(),
            routeName: route?.name ?? "",
            currentStopName: currentStop?.clientName ?? (allStopsDone ? "All stops complete" : ""),
            currentStopAddress: currentStop?.clientAddress ?? "",
            currentStopNumber: min(currentStopIndex + 1, sortedStops.count),
            totalStops: sortedStops.count,
            completedStops: min(currentStopIndex, sortedStops.count)
        )
    }

    // MARK: - Private

    private func recordVisit(for stop: RouteStop) {
        guard !stop.isCustomStop, let startedAt = stopStartedAt, let context else { return }
        let minutes = max(0, now().timeIntervalSince(startedAt) / 60)
        let clientID = stop.clientID
        // Fetch and match by UUID: a #Predicate on `id` clashes with SwiftData's own id.
        guard let client = try? context.fetch(FetchDescriptor<Client>()).first(where: { $0.id == clientID }) else { return }
        client.totalVisits += 1
        client.totalServiceMinutes += minutes
        client.lastServiceDate = now()
    }

    private func saveCheckpoint() {
        guard let route, let stopStartedAt else { return }
        let checkpoint = Checkpoint(routeID: route.id, currentStopIndex: currentStopIndex, stopStartedAt: stopStartedAt)
        if let data = try? JSONEncoder().encode(checkpoint) {
            defaults.set(data, forKey: Self.checkpointKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.checkpointKey),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data) else {
            surfaces.endStray(keeping: nil)
            return
        }
        let routeID = checkpoint.routeID
        guard let context,
              let route = try? context.fetch(FetchDescriptor<PlowRoute>()).first(where: { $0.id == routeID }) else {
            // The route was deleted (or synced away) while it was active.
            defaults.removeObject(forKey: Self.checkpointKey)
            surfaces.endStray(keeping: nil)
            return
        }
        self.route = route
        // Stops can be removed while the app is closed; never point past the end.
        currentStopIndex = min(max(0, checkpoint.currentStopIndex), route.sortedStops.count)
        stopStartedAt = checkpoint.stopStartedAt
        isFirstStopPromptPending = false
        surfaces.endStray(keeping: routeID)
        surfaces.resume(progress)
    }
}

/// The route's position, as the Live Activity and the home-screen widget show it.
struct RouteProgress: Equatable {
    var routeID: UUID
    var routeName: String
    var currentStopName: String
    var currentStopAddress: String
    var currentStopNumber: Int
    var totalStops: Int
    var completedStops: Int
}

/// Everything outside the app that shows route progress: the Live Activity and
/// the widget. A protocol so tests can run the store without touching either.
protocol RouteSurfaces {
    func start(_ progress: RouteProgress)
    func update(_ progress: RouteProgress)
    /// Re-attaches to the Live Activity after a relaunch, starting one if it's gone.
    func resume(_ progress: RouteProgress)
    func end(_ progress: RouteProgress)
    /// Ends any route Live Activity that doesn't belong to `routeID` (nil: all of them).
    func endStray(keeping routeID: UUID?)
}
