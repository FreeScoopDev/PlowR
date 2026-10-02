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
    static let shared = ActiveRouteStore(sites: SystemSiteWatching())

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
        /// `stopChangedUnseen`, kept: iCloud can move the route on while the
        /// app is in the background, and iOS can end the app before the user
        /// has seen the new stop. nil in a checkpoint from before it existed.
        var stopChangedUnseen: Bool?
        /// `runID`, kept so a relaunch keeps writing to this run's Service
        /// Log records. nil in a checkpoint from before it existed.
        var runID: UUID?
        /// `runStartedAt`, kept with it. nil in a checkpoint from before it existed.
        var runStartedAt: Date?
        /// `skippedStopIDs`, kept. nil in a checkpoint from before it existed.
        var skippedStopIDs: [UUID]?
        /// `site`, kept. nil when nothing was seen yet, or in a checkpoint
        /// from before it existed.
        var site: SiteTimes?
    }

    /// What completing the current stop did, so callers (the screen, Siri,
    /// Control Center) can say what actually happened.
    enum CompletionResult: Equatable {
        case advanced(nextStopIndex: Int)
        case finishedLastStop
        case noActiveRoute
        case allStopsAlreadyDone
        /// The stop the caller meant is no longer the current one (it was
        /// deleted or moved on another device). Nothing was recorded.
        case stopChanged
    }

    private(set) var route: PlowRoute?
    /// Copied at start/restore so ending a route never has to read a model
    /// that iCloud sync may already have deleted.
    private var routeID: UUID?
    private var routeName = ""
    /// The last progress shown on the Live Activity/widget, so ending a route
    /// that was deleted elsewhere never has to read the deleted models.
    private var lastProgress: RouteProgress?
    private(set) var currentStopIndex = 0
    /// Which stop is current, by identity. The index alone can't survive a
    /// reorder: after one, "the stop at the index" is a different client.
    private(set) var currentStopID: UUID?
    private(set) var stopStartedAt: Date?
    /// This run of the route, from `start(_:)` to `end()`. A stop's Service
    /// Log record is keyed by run and stop, so running the route again next
    /// week makes new records instead of overwriting last week's.
    private(set) var runID: UUID?
    /// When this run started: the day a stop's work is dated by when the
    /// stop's own start isn't known (Record Services opened from the recap).
    private(set) var runStartedAt: Date?
    /// Stops left out of this run (skipped today, or before where it was
    /// started from). They stay on the route; the run goes as if they weren't
    /// there: its stops, numbers, progress, Siri and the Live Activity.
    private(set) var skippedStopIDs: Set<UUID> = []

    /// True from `start(_:)` until the screen has offered to notify the first
    /// client. A route restored after a relaunch does not offer it again.
    var isFirstStopPromptPending = false

    /// The current stop changed without the user (iCloud removed or moved the
    /// stop they were at) and they haven't seen the new one on the route
    /// screen yet. Siri and Control Center won't complete a stop the user
    /// hasn't seen: at the old stop, they'd credit the next client's visit.
    private(set) var stopChangedUnseen = false

    /// When the crew got to the current stop and left it, as GPS saw it.
    private(set) var site = SiteTimes()
    /// Completed stops still waiting on GPS to see the crew leave. Not the
    /// route's: they outlive End Route.
    private(set) var departures: [PendingDeparture]

    private var context: ModelContext?
    private let defaults: UserDefaults
    private let surfaces: RouteSurfaces
    private let sites: SiteWatching
    private let now: () -> Date
    private let fetchRoutes: (ModelContext) throws -> [PlowRoute]
    static let checkpointKey = "activeRouteCheckpoint"

    init(defaults: UserDefaults = .standard,
         surfaces: RouteSurfaces = SystemRouteSurfaces(),
         sites: SiteWatching = NoSiteWatching(),
         now: @escaping () -> Date = Date.init,
         fetchRoutes: @escaping (ModelContext) throws -> [PlowRoute] = { try $0.fetch(FetchDescriptor<PlowRoute>()) }) {
        self.defaults = defaults
        self.surfaces = surfaces
        self.sites = sites
        departures = SiteDepartures.load(from: defaults)
        self.now = now
        self.fetchRoutes = fetchRoutes
    }

    // MARK: - Derived

    var isActive: Bool { route != nil }
    /// This run's stops, in order: the route's, less any left out of the run.
    var sortedStops: [RouteStop] {
        (route?.sortedStops ?? []).filter { !skippedStopIDs.contains($0.id) }
    }

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
        updateSites()
        // A route (or its stops) can be deleted or reordered on another device
        // while this one is mid-route. Re-check whenever the store changes;
        // the app also calls validate() when it becomes active.
        for name in [ModelContext.didSave, Notification.Name.NSPersistentStoreRemoteChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.validate() }
            }
        }
    }

    /// Begins `route` at its first stop, leaving `skipping` out of this run.
    /// Replaces any route already active.
    func start(_ route: PlowRoute, skipping: Set<UUID> = []) {
        if isActive { end() }
        // A new run. Last run's times and recorded services would otherwise
        // show its stops as done before they're visited.
        for stop in route.stops ?? [] {
            stop.actualMinutes = 0
            stop.completedServiceIDs = []
            stop.completedNotes = ""
        }
        self.route = route
        routeID = route.id
        routeName = route.name
        runID = UUID()
        runStartedAt = now()
        skippedStopIDs = skipping
        currentStopIndex = 0
        currentStopID = currentStop?.id
        stopStartedAt = now()
        site = SiteTimes()
        isFirstStopPromptPending = true
        stopChangedUnseen = false
        saveCheckpoint()
        lastProgress = progress
        surfaces.start(progress)
        updateSites()
    }

    /// Records the current stop's visit on its client and in the Service Log,
    /// and moves to the next stop. On the last stop, moves past it: the route
    /// is then "all stops done" and waits for `end()`, so the recap can still
    /// be reviewed.
    ///
    /// `expecting:` is the stop the caller means (the one on screen, or
    /// `currentStopID` for Siri) and is required, so no caller can skip it. If
    /// sync has changed the current stop since, nothing is recorded
    /// (`.stopChanged`): a visit is never credited to a client who wasn't visited.
    @discardableResult
    func completeCurrentStop(expecting stopID: UUID) -> CompletionResult {
        moveOn(expecting: stopID, recording: true)
    }

    /// Moves past the current stop without recording a visit: no time, no
    /// visit on the client, nothing in the Service Log. For a stop checked and
    /// found below its contract's snow trigger (the check is recorded by the
    /// caller, TriggerChecks). The run's recap shows it as not serviced.
    @discardableResult
    func passCurrentStop(expecting stopID: UUID) -> CompletionResult {
        moveOn(expecting: stopID, recording: false)
    }

    private func moveOn(expecting stopID: UUID, recording: Bool) -> CompletionResult {
        validate()
        guard isActive else { return .noActiveRoute }
        guard let stop = currentStop else {
            // Past the end. Either the caller's stop really was completed
            // (a double tap), or it was the last stop and was deleted elsewhere.
            return sortedStops.contains { $0.id == stopID } ? .allStopsAlreadyDone : .stopChanged
        }
        guard stopID == stop.id else { return .stopChanged }
        if recording { recordVisit(for: stop) }
        currentStopIndex += 1
        currentStopID = currentStop?.id
        stopStartedAt = now()
        site = SiteTimes()
        stopChangedUnseen = false
        saveCheckpoint()
        lastProgress = progress
        surfaces.update(progress)
        updateSites()
        // Saved now, not left to autosave: Siri completes stops with the app
        // in the background, which may be suspended before autosave runs.
        try? context?.save()
        return currentStop == nil ? .finishedLastStop : .advanced(nextStopIndex: currentStopIndex)
    }

    /// The route screen showed the current stop, with the app in front.
    func markCurrentStopSeen() {
        guard stopChangedUnseen else { return }
        stopChangedUnseen = false
        saveCheckpoint()
    }

    /// Whether `stopID` is behind the current stop: completed on this run.
    /// The route screen's notify sheet can outlive its stop being completed by
    /// Siri or Control Center; that isn't "changed on another device".
    func isBehindCurrentStop(_ stopID: UUID) -> Bool {
        guard let index = sortedStops.firstIndex(where: { $0.id == stopID }) else { return false }
        return index < currentStopIndex
    }

    /// Finishes the route: clears the checkpoint and ends the Live Activity.
    func end() {
        guard isActive else { return }
        surfaces.end(progress)
        clearState()
        updateSites()
    }

    // MARK: - Arrival and departure (GPS)

    /// The phone came into the area around the stop with this ID
    /// (`SiteMonitor`): the current stop's arrival, or, for a completed stop
    /// still awaiting its departure, a sign the crew wasn't there when it was
    /// completed, so a later exit isn't leaving it. `placedAt`: when the
    /// area was placed this launch, if it was.
    func siteEntered(_ id: String, at time: Date, placedAt: Date? = nil) {
        if let currentStopID, id == currentStopID.uuidString, let stopStartedAt, time >= stopStartedAt {
            site.entered(at: time, settleFrom: max(stopStartedAt, placedAt ?? stopStartedAt))
            saveCheckpoint()
        }
        if departures.contains(where: { $0.stopID.uuidString == id }) {
            departures.removeAll { $0.stopID.uuidString == id }
            SiteDepartures.save(departures, to: defaults)
            updateSites()
        }
    }

    /// The phone went out of the area around the stop with this ID: for the
    /// current stop, leaving it (unless it comes back in); for a completed
    /// stop awaiting its departure, the departure, added to its record.
    func siteExited(_ id: String, at time: Date) {
        if let currentStopID, id == currentStopID.uuidString, let stopStartedAt, time >= stopStartedAt {
            site.exited(at: time)
            saveCheckpoint()
        }
        guard let index = departures.firstIndex(where: { $0.stopID.uuidString == id }) else { return }
        let pending = departures.remove(at: index)
        SiteDepartures.save(departures, to: defaults)
        let elapsed = time.timeIntervalSince(pending.completedAt)
        if elapsed >= 0, elapsed <= SiteDepartures.window, let context,
           let record = ServiceLog.runRecord(run: pending.runID, stop: pending.stopID, in: context) {
            record.leftAt = time
            // Saved now: iOS woke the app in the background for this.
            try? context.save()
        }
        updateSites()
    }

    /// Has iOS watch the current stop's area and those of completed stops
    /// still awaiting a departure, and nothing else. A stop with no pin
    /// (0, 0) has no area. Not while a saved route is waiting to be restored:
    /// its stop's area would be removed, then placed again.
    private func updateSites() {
        if route == nil, defaults.data(forKey: Self.checkpointKey) != nil { return }
        var current = SiteDepartures.current(departures, now: now())
        // A stop awaiting a departure from an earlier run that's current
        // again (the route run a second time): leaving it now is this run's.
        if let currentStopID { current.removeAll { $0.stopID == currentStopID } }
        if current != departures {
            departures = current
            SiteDepartures.save(departures, to: defaults)
        }
        var areas = departures.map { SiteArea(id: $0.stopID.uuidString, latitude: $0.latitude, longitude: $0.longitude) }
        if let stop = currentStop, stop.latitude != 0 || stop.longitude != 0 {
            areas.append(SiteArea(id: stop.id.uuidString, latitude: stop.latitude, longitude: stop.longitude))
        }
        sites.watch(areas)
    }

    private enum Lookup {
        case found(PlowRoute), missing, unknown
        var isMissing: Bool { if case .missing = self { true } else { false } }
    }

    /// Ends the route if it no longer exists (deleted here or synced away) and
    /// re-finds the current stop if the stops were reordered or removed.
    /// Runs on every store save, on remote changes and when the app is active.
    func validate() {
        guard let route, let routeID else {
            // A launch that couldn't read the store left the route unrestored;
            // try again now (this runs on saves and whenever the app is active).
            if context != nil, defaults.data(forKey: Self.checkpointKey) != nil { restore() }
            // Departures awaited after End Route stop being watched in time.
            updateSites()
            return
        }
        if route.isDeleted || lookup(routeID).isMissing {
            // Never read the deleted models: end with what was last shown.
            surfaces.end(lastProgress ?? progress)
            clearState()
            updateSites()
            return
        }
        let beforeProgress = lastProgress
        let stopChanged = reconcile(stopID: currentStopID, index: currentStopIndex)
        if stopChanged {
            stopStartedAt = now()
            site = SiteTimes()
            stopChangedUnseen = true
        }
        if stopChanged || progress != beforeProgress {
            saveCheckpoint()
            lastProgress = progress
            surfaces.update(progress)
        }
        // Also when only the current stop's pin moved, with its client's.
        updateSites()
    }

    /// The one rule for "where are we now", shared by `validate()` and
    /// `restore()` so the two can't drift apart (they did once: a relaunch
    /// handed a deleted stop's timer to the next client). Finds the stop by
    /// identity; if it's gone, stays at the same position, never past the end.
    /// Returns true if a different stop (or none) is now current, in which case
    /// the caller must start a fresh timer.
    private func reconcile(stopID: UUID?, index: Int) -> Bool {
        let stops = sortedStops
        if let stopID, let found = stops.firstIndex(where: { $0.id == stopID }) {
            currentStopIndex = found
        } else {
            currentStopIndex = min(max(0, index), stops.count)
        }
        currentStopID = currentStop?.id
        return currentStopID != stopID
    }

    /// For Delete Account & Data: ends any route and removes every trace of it
    /// (checkpoint, Live Activities, the widget's saved route), active or not.
    func eraseAll() {
        end()
        defaults.removeObject(forKey: Self.checkpointKey)
        surfaces.clear()
        departures = []
        SiteDepartures.save([], to: defaults)
        updateSites()
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
            completedStops: min(currentStopIndex, sortedStops.count),
            currentStopID: currentStopID
        )
    }

    // MARK: - Private

    private func recordVisit(for stop: RouteStop) {
        guard let startedAt = stopStartedAt else { return }
        let finishedAt = now()
        let minutes = max(0, finishedAt.timeIntervalSince(startedAt) / 60)
        // The stop's time this run, which the route list, the dashboard, the
        // route map and the recap read as "done". Nothing wrote it before. At
        // least a minute, so a quick stop still reads as done.
        stop.actualMinutes = max(1, Int(minutes.rounded()))
        guard !stop.isCustomStop, let context else { return }
        let clientID = stop.clientID
        // Fetch and match by UUID: a #Predicate on `id` clashes with SwiftData's own id.
        guard let client = try? context.fetch(FetchDescriptor<Client>()).first(where: { $0.id == clientID }) else { return }
        client.totalVisits += 1
        client.totalServiceMinutes += minutes
        client.lastServiceDate = finishedAt
        guard let runID else { return }
        let record = ServiceLog.recordStop(stop, of: client, run: runID,
                                           operatorID: route?.operatorID ?? client.operatorID,
                                           startedAt: startedAt, finishedAt: finishedAt, minutes: minutes,
                                           in: context)
        record.arrivedAt = site.arrivedAt
        record.leftAt = site.leftAt
        // Not seen leaving yet: still there, or never seen there at all.
        // Watched for its departure (SiteDepartures says for how long).
        if site.leftAt == nil, stop.latitude != 0 || stop.longitude != 0 {
            departures.removeAll { $0.stopID == stop.id }
            departures.append(PendingDeparture(runID: runID, stopID: stop.id, completedAt: finishedAt,
                                               latitude: stop.latitude, longitude: stop.longitude))
            SiteDepartures.save(departures, to: defaults)
        }
    }

    private func clearState() {
        route = nil
        routeID = nil
        routeName = ""
        runID = nil
        runStartedAt = nil
        skippedStopIDs = []
        lastProgress = nil
        currentStopIndex = 0
        currentStopID = nil
        stopStartedAt = nil
        site = SiteTimes()
        isFirstStopPromptPending = false
        stopChangedUnseen = false
        defaults.removeObject(forKey: Self.checkpointKey)
    }

    /// found / missing / unknown. No context or a failed fetch is "unknown",
    /// never "missing": only a route that is really gone may end a route.
    private func lookup(_ id: UUID) -> Lookup {
        guard let context else { return .unknown }
        // Match by UUID: a #Predicate on `id` clashes with SwiftData's own id.
        guard let routes = try? fetchRoutes(context) else { return .unknown }
        if let route = routes.first(where: { $0.id == id && !$0.isDeleted }) { return .found(route) }
        return .missing
    }

    private func saveCheckpoint() {
        guard let routeID, let stopStartedAt else { return }
        let checkpoint = Checkpoint(routeID: routeID, currentStopIndex: currentStopIndex,
                                    currentStopID: currentStopID, stopStartedAt: stopStartedAt,
                                    stopChangedUnseen: stopChangedUnseen, runID: runID,
                                    runStartedAt: runStartedAt,
                                    skippedStopIDs: skippedStopIDs.isEmpty ? nil : Array(skippedStopIDs),
                                    site: site == SiteTimes() ? nil : site)
        if let data = try? JSONEncoder().encode(checkpoint) {
            defaults.set(data, forKey: Self.checkpointKey)
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.checkpointKey) else {
            surfaces.clear()          // Nothing in progress: no Live Activity or "active" widget may linger.
            return
        }
        guard let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data) else {
            defaults.removeObject(forKey: Self.checkpointKey)      // unreadable
            surfaces.clear()
            return
        }
        let route: PlowRoute
        switch lookup(checkpoint.routeID) {
        case .found(let found):
            route = found
        case .missing:
            // Deleted while the app was closed.
            defaults.removeObject(forKey: Self.checkpointKey)
            surfaces.clear()
            return
        case .unknown:
            // Can't tell (store not readable yet). Keep the checkpoint;
            // validate() retries on the next save or return to the app.
            return
        }
        self.route = route
        routeID = route.id
        routeName = route.name
        runID = checkpoint.runID ?? UUID()
        runStartedAt = checkpoint.runStartedAt ?? checkpoint.stopStartedAt
        skippedStopIDs = Set(checkpoint.skippedStopIDs ?? [])
        let stopChanged = reconcile(stopID: checkpoint.currentStopID, index: checkpoint.currentStopIndex)
        // The saved timer belongs to the saved stop only.
        stopStartedAt = stopChanged ? now() : checkpoint.stopStartedAt
        site = stopChanged ? SiteTimes() : (checkpoint.site ?? SiteTimes())
        // Changed now, or before the app was ended and not seen since.
        stopChangedUnseen = stopChanged || (checkpoint.stopChangedUnseen ?? false)
        isFirstStopPromptPending = false
        lastProgress = progress
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
    /// The stop shown, for Control Center to name when it completes one.
    var currentStopID: UUID?
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
