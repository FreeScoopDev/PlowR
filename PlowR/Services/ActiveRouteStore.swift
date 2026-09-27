import CoreData
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
        /// The current stop itself, so a reorder or a removed earlier stop
        /// (e.g. from another device) can't move the route to a different
        /// client. nil once every stop is done.
        var currentStopID: UUID?
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
    /// Copied at start/restore so ending a route never has to read a model
    /// that iCloud sync may already have deleted.
    private var routeID: UUID?
    private var routeName = ""
    private(set) var currentStopIndex = 0
    /// Which stop is current, by identity. The index alone can't survive a
    /// reorder: after one, "the stop at the index" is a different client.
    private var currentStopID: UUID?
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
        // A route (or its stops) can be deleted or reordered on another device
        // while this one is mid-route. Re-check whenever the store changes;
        // the app also calls validate() when it becomes active.
        for name in [ModelContext.didSave, Notification.Name.NSPersistentStoreRemoteChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.validate() }
            }
        }
    }

    /// Begins `route` at its first stop. Replaces any route already active.
    func start(_ route: PlowRoute) {
        if isActive { end() }
        self.route = route
        routeID = route.id
        routeName = route.name
        currentStopIndex = 0
        currentStopID = currentStop?.id
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
        validate()
        guard isActive else { return .noActiveRoute }
        guard let stop = currentStop else { return .allStopsAlreadyDone }
        recordVisit(for: stop)
        currentStopIndex += 1
        currentStopID = currentStop?.id
        stopStartedAt = now()
        saveCheckpoint()
        surfaces.update(progress)
        return currentStop == nil ? .finishedLastStop : .advanced(nextStopIndex: currentStopIndex)
    }

    /// Finishes the route: clears the checkpoint and ends the Live Activity.
    func end() {
        guard isActive else { return }
        surfaces.end(progress)
        clearState()
    }

    /// Ends the route if it no longer exists (deleted here or synced away) and
    /// re-finds the current stop if the stops were reordered or removed.
    func validate() {
        guard let route, let routeID else { return }
        // Without a context the route can't be looked up; that is "unknown",
        // not "deleted", so only the model's own flag counts then.
        let gone = route.isDeleted || (context != nil && fetchRoute(id: routeID) == nil)
        if gone {
            surfaces.end(progress)
            clearState()
            return
        }
        let before = currentStopIndex
        if let currentStopID, let index = sortedStops.firstIndex(where: { $0.id == currentStopID }) {
            currentStopIndex = index
        } else {
            currentStopIndex = min(currentStopIndex, sortedStops.count)
            currentStopID = currentStop?.id
        }
        if currentStopIndex != before {
            saveCheckpoint()
            surfaces.update(progress)
        }
    }

    /// For Delete Account & Data: ends any route and removes every trace of it
    /// (checkpoint, Live Activities, the widget's saved route), active or not.
    func eraseAll() {
        end()
        defaults.removeObject(forKey: Self.checkpointKey)
        surfaces.clear()
    }

    // MARK: - Progress for the Live Activity and widget

    var progress: RouteProgress {
        RouteProgress(
            routeID: routeID ?? UUID(),
            routeName: routeName,
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

    private func clearState() {
        route = nil
        routeID = nil
        routeName = ""
        currentStopIndex = 0
        currentStopID = nil
        stopStartedAt = nil
        isFirstStopPromptPending = false
        defaults.removeObject(forKey: Self.checkpointKey)
    }

    private func fetchRoute(id: UUID) -> PlowRoute? {
        // Match by UUID: a #Predicate on `id` clashes with SwiftData's own id.
        try? context?.fetch(FetchDescriptor<PlowRoute>()).first { $0.id == id && !$0.isDeleted }
    }

    private func saveCheckpoint() {
        guard let routeID, let stopStartedAt else { return }
        let checkpoint = Checkpoint(routeID: routeID, currentStopIndex: currentStopIndex,
                                    currentStopID: currentStopID, stopStartedAt: stopStartedAt)
        if let data = try? JSONEncoder().encode(checkpoint) {
            defaults.set(data, forKey: Self.checkpointKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.checkpointKey) else {
            surfaces.clear()          // Nothing in progress: no Live Activity or "active" widget may linger.
            return
        }
        guard let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
              let route = fetchRoute(id: checkpoint.routeID) else {
            // Unreadable, or the route was deleted while the app was closed.
            defaults.removeObject(forKey: Self.checkpointKey)
            surfaces.clear()
            return
        }
        self.route = route
        routeID = route.id
        routeName = route.name
        let stops = route.sortedStops
        if let id = checkpoint.currentStopID, let index = stops.firstIndex(where: { $0.id == id }) {
            currentStopIndex = index
        } else if checkpoint.currentStopID == nil, checkpoint.currentStopIndex >= stops.count {
            currentStopIndex = stops.count              // every stop was already done
        } else {
            // The saved stop is gone; stay at the same position, never past the end.
            currentStopIndex = min(max(0, checkpoint.currentStopIndex), stops.count)
        }
        currentStopID = currentStop?.id
        stopStartedAt = checkpoint.stopStartedAt
        isFirstStopPromptPending = false
        surfaces.resume(progress)
        saveCheckpoint()
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
    /// After a relaunch: adopts this route's still-running Live Activity (one
    /// only), ends every other route Live Activity, and starts one if none is left.
    func resume(_ progress: RouteProgress)
    func end(_ progress: RouteProgress)
    /// No route is active: ends every route Live Activity and clears a widget
    /// still showing a route as active.
    func clear()
}
