import CoreData
import Foundation
import OSLog
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

    /// What `undoLastCompletion(expecting:)` did.
    enum UndoResult: Equatable {
        case undone
        /// No completion to undo: none yet, already undone, the last stop
        /// (the recap opens instead), passed below trigger, or the route ended.
        case nothingToUndo
        /// The stop the caller meant isn't the one last completed, or the
        /// route moved on since (another stop completed, a change from
        /// another device). Nothing was changed.
        case stopChanged
        /// More than `undoWindow` since it was completed. Nothing was changed.
        case expired
        /// Work was saved on the stop's record since it was completed (Record
        /// Services left open while Siri or Control Center completed the
        /// stop: services, notes, photos, an invoice). Undoing would delete
        /// or overwrite it, so nothing was changed.
        case recordChanged
    }

    /// How long a completed stop can be undone.
    static let undoWindow: TimeInterval = 30

    /// What the route screen's Undo bar shows: the stop last completed, and
    /// when the chance to undo it ends.
    struct UndoOffer: Equatable {
        var stopID: UUID
        var clientName: String
        var expiresAt: Date
    }

    /// What completing a stop changed, each value as it was before, so Undo
    /// can put it back exactly. In memory only: if iOS ends the app inside
    /// the window, the completion stands (nothing new to erase, either).
    struct UndoableCompletion {
        var routeID: UUID
        var runID: UUID?
        var stopID: UUID
        var stopIndex: Int
        var clientName: String
        var completedAt: Date
        /// The run's stops then: any change to them (sync) ends the window.
        var stopIDs: [UUID]
        /// The stop that became current; set once the route has moved on.
        var nextStopID: UUID?
        var stopStartedAt: Date?
        var site: SiteTimes
        var stopChangedUnseen: Bool
        var actualMinutes: Int
        var departures: [PendingDeparture]
        var client: UndoClientTotals?
        /// The record completing wrote to; nil when it wrote none (a custom
        /// stop, a client not found).
        var record: ServiceRecord?
        /// Its fields before, when it existed already (Record Services, the
        /// Schedule): put back by Undo. nil when completing made it: deleted.
        var recordBefore: ServiceRecord.Fields?
        /// Its fields and photos as completing left them. Anything written to
        /// it since (but its departure, `leftAt`, which Undo takes back too)
        /// refuses the undo: `.recordChanged`.
        var recordAfter: ServiceRecord.Fields?
        var photosAfter: Set<UUID> = []
        var visit: UndoVisitState?
        /// The next visit of a repeating series, added when the visit was completed.
        var addedVisits: [ScheduledVisit] = []
        /// The services the "Done:" button recorded on the stop (it had none
        /// before): Undo takes them back off. Empty for a plain completion.
        var servicesAdded: [String] = []
    }

    /// What a completion added to a client's totals, and the last service
    /// date before it. Undo takes back only what it added: a change synced
    /// from another device in the meantime stands.
    struct UndoClientTotals {
        var client: Client
        var totalServiceMinutes: Double
        var addedMinutes: Double
        var lastServiceDate: Date?
        var finishedAt: Date
    }

    /// A day's visit before a completion completed it.
    struct UndoVisitState {
        var visit: ScheduledVisit
        var status: VisitStatus
        var completedAt: Date?
        var serviceLogged: Bool
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
    /// The last completion, while it can still be undone. Cleared by the
    /// next completion or pass, `end()`, and a route change `validate()` finds.
    private var lastCompletion: UndoableCompletion?

    private var context: ModelContext?
    private let defaults: UserDefaults
    private let surfaces: RouteSurfaces
    private let sites: SiteWatching
    private let now: () -> Date
    private let fetchRoutes: (ModelContext) throws -> [PlowRoute]
    private let save: (ModelContext) throws -> Void
    private static let log = Logger(subsystem: "Scoops.PlowR", category: "ActiveRouteStore")
    static let checkpointKey = "activeRouteCheckpoint"

    init(defaults: UserDefaults = .standard,
         surfaces: RouteSurfaces = SystemRouteSurfaces(),
         sites: SiteWatching = NoSiteWatching(),
         now: @escaping () -> Date = Date.init,
         fetchRoutes: @escaping (ModelContext) throws -> [PlowRoute] = { try $0.fetch(FetchDescriptor<PlowRoute>()) },
         save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.defaults = defaults
        self.surfaces = surfaces
        self.sites = sites
        departures = SiteDepartures.load(from: defaults)
        self.now = now
        self.fetchRoutes = fetchRoutes
        self.save = save
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

    /// The completion the route screen can offer to undo, until `expiresAt`.
    /// None once its record has been written to since (Record Services
    /// saved), so the bar closes then; reading the record here makes the
    /// screen follow it.
    var undoOffer: UndoOffer? {
        guard let undo = lastCompletion, !recordFieldsChanged(since: undo) else { return nil }
        return UndoOffer(stopID: undo.stopID, clientName: undo.clientName,
                         expiresAt: undo.completedAt.addingTimeInterval(Self.undoWindow))
    }

    /// Whether the completion's record was deleted or a field of it written
    /// since completing, leaving out its departure time.
    private func recordFieldsChanged(since undo: UndoableCompletion) -> Bool {
        guard let record = undo.record, let after = undo.recordAfter else { return false }
        if record.isDeleted { return true }
        var now = ServiceRecord.Fields(of: record)
        now.leftAt = after.leftAt
        return now != after
    }

    /// Fields, or photos taken for it since completing.
    private func recordChanged(since undo: UndoableCompletion) -> Bool {
        if recordFieldsChanged(since: undo) { return true }
        guard let record = undo.record, let context else { return false }
        return !Set(ServiceLog.photos(of: record, in: context).map(\.id)).isSubset(of: undo.photosAfter)
    }

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
        // Never making the poster wait (MainActorNotice), and a save only of
        // this store's own database: one in another (the tests make many)
        // ran validate() inside that save, reading this database, which
        // deadlocked too.
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            let saved = (note.object as? ModelContext)?.container
            MainActorNotice.run { [weak self] in
                guard let self, Self.isOwnSave(saved, of: self.context) else { return }
                self.validate()
            }
        }
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil,
                                               queue: nil) { [weak self] _ in
            MainActorNotice.run { [weak self] in self?.validate() }
        }
    }

    /// Whether a save in `saved` is one of this store's database (any of its
    /// contexts: the app's background work saves through its own).
    static func isOwnSave(_ saved: ModelContainer?, of context: ModelContext?) -> Bool {
        guard let saved, let context else { return false }
        return saved === context.container
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
            stop.cantServiceReason = ""
            stop.cantServiceAt = nil
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
        lastCompletion = nil
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
    ///
    /// `recordingServices`: the services the route screen's "Done:" button
    /// named (OneTapServices), recorded with this completion and only if it
    /// happens, and only when nothing is recorded for the stop yet
    /// (`ServiceLog.hasNothingRecorded`): they never replace or add to
    /// services, prices or custom items already there, or touch a bill.
    /// Undo takes them back off. Siri, Control Center and Below Trigger pass
    /// none: they don't show which services would be recorded.
    @discardableResult
    func completeCurrentStop(expecting stopID: UUID, recordingServices serviceIDs: [String] = []) -> CompletionResult {
        moveOn(expecting: stopID, recording: true, services: serviceIDs)
    }

    /// Moves past the current stop without recording a visit: no time, no
    /// visit on the client, nothing in the Service Log. For a stop checked and
    /// found below its contract's snow trigger (the check is recorded by the
    /// caller, TriggerChecks). The run's recap shows it as not serviced.
    @discardableResult
    func passCurrentStop(expecting stopID: UUID) -> CompletionResult {
        moveOn(expecting: stopID, recording: false, services: [])
    }

    /// Can't Service: moves past the current stop as `passCurrentStop` does
    /// (no visit, time, services or Service Log record; can't be undone, and
    /// ends the last completion's Undo), and keeps `reason` and the time on
    /// the stop, only when the route really moved past it. On `.stopChanged`
    /// or a stop already behind, nothing is written.
    @discardableResult
    func skipCurrentStop(expecting stopID: UUID, reason: String) -> CompletionResult {
        let result = moveOn(expecting: stopID, recording: false, services: [])
        switch result {
        case .advanced, .finishedLastStop:
            guard let stop = sortedStops.first(where: { $0.id == stopID }) else { return result }
            stop.cantServiceReason = reason
            stop.cantServiceAt = now()
            // Saved now, as moveOn saves: not left to autosave.
            try? context?.save()
        case .noActiveRoute, .allStopsAlreadyDone, .stopChanged: break
        }
        return result
    }

    private func moveOn(expecting stopID: UUID, recording: Bool, services: [String]) -> CompletionResult {
        validate()
        guard isActive else { return .noActiveRoute }
        guard let stop = currentStop else {
            // Past the end. Either the caller's stop really was completed
            // (a double tap), or it was the last stop and was deleted elsewhere.
            return sortedStops.contains { $0.id == stopID } ? .allStopsAlreadyDone : .stopChanged
        }
        guard stopID == stop.id else { return .stopChanged }
        // Taken before anything changes: Undo puts back exactly this. A pass
        // (no recording) can't be undone, and ends the last one's chance.
        lastCompletion = nil
        var undo = recording ? beforeCompleting(stop) : nil
        // The crew was at this stop: an earlier stop's exit seen from now on
        // isn't when they left it (the areas overlap, or it came too late).
        if !departures.isEmpty {
            departures = []
            SiteDepartures.save(departures, to: defaults)
        }
        if var completion = undo {
            recordVisit(for: stop, services: services, undo: &completion)
            undo = completion
        }
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
        guard let next = currentStop else { return .finishedLastStop }
        // Not after the last stop: the recap opens, and edits a stop itself.
        if var completion = undo {
            completion.nextStopID = next.id
            lastCompletion = completion
        }
        return .advanced(nextStopIndex: currentStopIndex)
    }

    /// The route's side of `stop` before it's completed (its record, visit
    /// and client are added by `recordVisit`, which reads them first).
    private func beforeCompleting(_ stop: RouteStop) -> UndoableCompletion? {
        guard let routeID else { return nil }
        return UndoableCompletion(routeID: routeID, runID: runID, stopID: stop.id, stopIndex: currentStopIndex,
                                  clientName: stop.clientName, completedAt: now(),
                                  stopIDs: sortedStops.map(\.id), stopStartedAt: stopStartedAt, site: site,
                                  stopChangedUnseen: stopChangedUnseen, actualMinutes: stop.actualMinutes,
                                  departures: departures)
    }

    /// Takes back the stop just completed (`expecting`, the one the Undo bar
    /// named): its visit on the client, its Service Log record (deleted if
    /// completing made it, its fields put back if Record Services had), the
    /// day's visit it completed, its time, and the route goes back to it,
    /// with its timer, arrival and the departures being watched as they were.
    /// Refused, changing nothing, once the route has moved on in any other
    /// way, `undoWindow` has passed, or work was saved on the stop's record
    /// since (`.recordChanged`). A text already sent stays sent. The
    /// client's totals lose only what this completion added.
    @discardableResult
    func undoLastCompletion(expecting stopID: UUID) -> UndoResult {
        validate()
        guard let undo = lastCompletion, isActive else { return .nothingToUndo }
        guard undo.stopID == stopID else { return .stopChanged }
        let stops = sortedStops
        guard routeID == undo.routeID, runID == undo.runID, currentStopIndex == undo.stopIndex + 1,
              currentStopID == undo.nextStopID, stops.map(\.id) == undo.stopIDs,
              stops.indices.contains(undo.stopIndex) else {
            lastCompletion = nil
            return .stopChanged
        }
        guard now().timeIntervalSince(undo.completedAt) <= Self.undoWindow else {
            lastCompletion = nil
            return .expired
        }
        guard !recordChanged(since: undo) else {
            lastCompletion = nil
            return .recordChanged
        }
        lastCompletion = nil
        let stop = stops[undo.stopIndex]
        stop.actualMinutes = undo.actualMinutes
        // The "Done:" button's services: the stop had none before.
        if !undo.servicesAdded.isEmpty, stop.completedServiceIDs == undo.servicesAdded {
            stop.completedServiceIDs = []
        }
        if let totals = undo.client, !totals.client.isDeleted {
            let client = totals.client
            client.totalVisits = max(0, client.totalVisits - 1)
            // Exactly as before when nothing else added since; else less
            // what this completion added.
            if client.totalServiceMinutes == totals.totalServiceMinutes + totals.addedMinutes {
                client.totalServiceMinutes = totals.totalServiceMinutes
            } else {
                client.totalServiceMinutes = max(0, client.totalServiceMinutes - totals.addedMinutes)
            }
            if client.lastServiceDate == totals.finishedAt { client.lastServiceDate = totals.lastServiceDate }
        }
        if let record = undo.record, !record.isDeleted, let context {
            if let before = undo.recordBefore {
                before.restore(to: record)
            } else {
                // Billed only on the invoice already made for its visit
                // (billFromVisit), which stays: nothing was billed since.
                ServiceLog.deleteRecord(record, in: context, evenIfInvoiced: true)
            }
        }
        if let state = undo.visit, !state.visit.isDeleted {
            state.visit.status = state.status
            state.visit.completedAt = state.completedAt
            state.visit.serviceLogged = state.serviceLogged
        }
        for added in undo.addedVisits where !added.isDeleted { context?.delete(added) }
        departures = undo.departures
        SiteDepartures.save(departures, to: defaults)
        currentStopIndex = undo.stopIndex
        currentStopID = stop.id
        stopStartedAt = undo.stopStartedAt
        site = undo.site
        stopChangedUnseen = undo.stopChangedUnseen
        saveCheckpoint()
        lastProgress = progress
        surfaces.update(progress)
        updateSites()
        try? context?.save()
        return .undone
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
        // The next route isn't the first: the route screen's tip is done.
        PlowRTips.routeRan()
        surfaces.end(progress)
        clearState()
        updateSites()
    }

    // MARK: - Arrival and departure (GPS)

    /// The phone came into the area around the stop with this ID
    /// (`SiteMonitor`): the current stop's arrival, or, for a completed stop
    /// still awaiting its departure, a sign the crew wasn't there when it was
    /// completed, so a later exit isn't leaving it. Not one dated before the
    /// stop was completed, delivered late (iOS holds events until PlowR can
    /// take them): the crew was there then, and their departure still counts.
    func siteEntered(_ id: String, at time: Date) {
        if let currentStopID, id == currentStopID.uuidString, let stopStartedAt, time >= stopStartedAt {
            site.entered(at: time)
            saveCheckpoint()
            atCurrentStop()
        }
        if departures.contains(where: { $0.stopID.uuidString == id && time >= $0.completedAt }) {
            departures.removeAll { $0.stopID.uuidString == id }
            SiteDepartures.save(departures, to: defaults)
            updateSites()
        }
    }

    /// iOS's first answer after the area with this ID was placed: the phone
    /// was already in it. For the current stop, no arrival can be given.
    func siteInsideWhenPlaced(_ id: String, at time: Date) {
        guard let currentStopID, id == currentStopID.uuidString, let stopStartedAt, time >= stopStartedAt else { return }
        site.insideWhenPlaced()
        saveCheckpoint()
        atCurrentStop()
    }

    /// The phone is in the current stop's area: an earlier stop's exit seen
    /// from now on isn't when they left it. iOS reports an exit only some way
    /// past the area's edge, so areas apart can still both hold the phone.
    private func atCurrentStop() {
        guard !departures.isEmpty else { return }
        departures = []
        SiteDepartures.save(departures, to: defaults)
        updateSites()
    }

    /// The phone went out of the area around the stop with this ID: for the
    /// current stop, leaving it (unless it comes back in); for a completed
    /// stop awaiting its departure, the departure, added to its record.
    func siteExited(_ id: String, at time: Date) {
        if let currentStopID, id == currentStopID.uuidString, let stopStartedAt, time >= stopStartedAt {
            site.exited(at: time)
            saveCheckpoint()
        }
        // One dated before the stop was completed, delivered late, isn't its
        // departure: they may have come back in since.
        guard let index = departures.firstIndex(where: { $0.stopID.uuidString == id && time >= $0.completedAt })
        else { return }
        let pending = departures.remove(at: index)
        SiteDepartures.save(departures, to: defaults)
        if time.timeIntervalSince(pending.completedAt) <= SiteDepartures.window, let context,
           let record = ServiceLog.runRecord(run: pending.runID, stop: pending.stopID, in: context) {
            record.leftAt = time
            // Saved now: iOS woke the app in the background for this. If it
            // fails, the time stays on the record in memory for the next save
            // (no second exit comes for this stop), and the failure is logged.
            do { try save(context) } catch {
                Self.log.error("Departure not saved: \(error.localizedDescription, privacy: .public)")
            }
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
        // One whose area overlaps the current stop's: going out of the current
        // stop would also go out of it, so its exit can't say when they left it.
        if let stop = currentStop, stop.latitude != 0 || stop.longitude != 0 {
            current.removeAll { SiteDepartures.overlaps($0, latitude: stop.latitude, longitude: stop.longitude) }
        }
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
        // The route changed under the last completion: undoing it now could
        // put back the wrong stop.
        if let undo = lastCompletion, stopChanged || sortedStops.map(\.id) != undo.stopIDs {
            lastCompletion = nil
        }
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
        lastCompletion = nil
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

    private func recordVisit(for stop: RouteStop, services: [String], undo: inout UndoableCompletion) {
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
        undo.client = .init(client: client, totalServiceMinutes: client.totalServiceMinutes, addedMinutes: minutes,
                            lastServiceDate: client.lastServiceDate, finishedAt: finishedAt)
        client.totalVisits += 1
        client.totalServiceMinutes += minutes
        client.lastServiceDate = finishedAt
        guard let runID else { return }
        // What the record and visit were before, read the way recordStop finds them.
        let target = ServiceLog.targetForStop(stop, of: client, run: runID, startedAt: startedAt, in: context)
        undo.recordBefore = target.record.map { ServiceRecord.Fields(of: $0) }
        let seriesBefore = target.visit.map { Set(ServiceLog.series(of: $0, in: context).map(\.id)) }
        if let visit = target.visit {
            undo.visit = .init(visit: visit, status: visit.status, completedAt: visit.completedAt,
                               serviceLogged: visit.serviceLogged)
        }
        // The "Done:" button's services, put on the stop for recordStop to
        // price (ServiceLog.lines, as Record Services' catalog prices), only
        // when nothing is recorded for it yet: asked again here, at the
        // moment of completing, as the button asked when it was drawn.
        let addingServices = !services.isEmpty
            && ServiceLog.hasNothingRecorded(for: stop, of: client, run: runID, startedAt: startedAt, in: context)
        if addingServices { stop.completedServiceIDs = services }
        let record = ServiceLog.recordStop(stop, of: client, run: runID,
                                           operatorID: route?.operatorID ?? client.operatorID,
                                           startedAt: startedAt, finishedAt: finishedAt, minutes: minutes,
                                           in: context)
        if addingServices {
            // Only what made it onto the record: a service deleted from the
            // catalog since the button was drawn has no line, and mustn't
            // count as recorded on the stop.
            let added = record.lines.map(\.serviceID).filter { services.contains($0) }
            stop.completedServiceIDs = added
            undo.servicesAdded = added
        }
        undo.record = record
        if let visit = target.visit, let seriesBefore {
            undo.addedVisits = ServiceLog.series(of: visit, in: context).filter { !seriesBefore.contains($0.id) }
        }
        record.arrivedAt = site.arrivedAt
        record.leftAt = site.leftAt
        undo.recordAfter = ServiceRecord.Fields(of: record)
        undo.photosAfter = Set(ServiceLog.photos(of: record, in: context).map(\.id))
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
        lastCompletion = nil
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
