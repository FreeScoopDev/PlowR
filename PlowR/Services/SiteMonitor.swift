import CoreLocation
import Foundation
import os
import UIKit

/// The app's one keeper of job-site areas: the current stop's, for arrival
/// and departure, and completed stops' still waiting on a departure.
///
/// Made at launch (`PlowRApp.init` calls `start()`), not by a screen: iOS
/// relaunches PlowR in the background when the phone crosses an area, and
/// holds the crossing until a monitor of the same name is open to take it.
/// `ActiveRouteStore` decides what is watched and what a crossing means; this
/// only places the areas and passes crossings on.
///
/// The areas are CoreLocation's `CLMonitor` conditions (legacy region
/// monitoring is deprecated). iOS keeps them, and its events, across
/// launches; each event carries its own time and whether the phone is in the
/// area, and iOS 18 adds why an area isn't being watched (`SiteLimit`).
@Observable
final class SiteMonitor: NSObject, CLLocationManagerDelegate, SiteWatching, SiteErasing {
    static let shared = SiteMonitor()

    /// About a property's size; also iOS's practical minimum.
    static let radius: CLLocationDistance = 100
    /// Only one monitor of a name can be open at a time.
    static let monitorName = "PlowRSites"

    /// The phone went out of the current stop's area: for the route screen's
    /// offer to text the next client (`ExitPrompt`). Each exit is a new
    /// value, so one left over from an exit the screen wasn't up for can't
    /// hide the next from the screen. `time`: as given to the route store.
    struct Exit: Equatable {
        var stopID: String
        var time: Date
        var token = UUID()
    }
    var lastExit: Exit?

    /// iOS said it can't watch the areas with approximate location (an
    /// event's `accuracyLimited`): the route screen says to turn Precise
    /// Location on, as when the location manager reports reduced accuracy.
    private(set) var accuracyLimited = false

    private let defaults: UserDefaults
    private let now: () -> Date
    private let route: () -> ActiveRouteStore
    private let makeSession: (CLServiceSession.AuthorizationRequirement) -> SiteSession
    /// iOS's monitor, once open (`open()`); a fake in tests.
    private var conditions: SiteConditions?
    /// Areas left from legacy region monitoring (PlowR 1.7 and before),
    /// stopped once the route says what it wants. The location manager, in
    /// the app.
    private var legacy: (any RegionMonitoring)?
    private var manager: CLLocationManager?
    private var opening = false
    private var protectedDataObservers: [NSObjectProtocol] = []
    /// The last change asked of the monitor, each waiting for the one before.
    private var applying: Task<Void, Never>?

    /// What the route wants watched. nil until the route has said: iOS keeps
    /// areas across launches, and they mustn't be cleared before the route
    /// is restored.
    private var wanted: [SiteArea]?
    /// What's placed, and where the phone was last heard to be in each, kept
    /// in preferences: iOS keeps the areas across launches, so the first
    /// answer after placing one has to be known as that after a relaunch too.
    private var placed: [PlacedSite]
    /// Every area to be removed from the monitor (Delete Account & Data).
    private var eraseOwed = false
    /// Every area to be placed afresh: Precise Location is back, and what iOS
    /// held from before isn't to be trusted.
    private var replaceAll = false

    private var session: SiteSession?
    private var sessionNeed: CLServiceSession.AuthorizationRequirement?
    /// The status last seen. iOS calls the authorization callback when the
    /// manager is made too, with nothing changed.
    private var authorization: CLAuthorizationStatus
    /// Approximate location watches no areas: none are placed then, and all
    /// are placed afresh once Precise Location is back.
    private var accuracy: CLAccuracyAuthorization

    /// Whether going from `old` to `new` means location was allowed only now.
    static func isNewlyAllowed(from old: CLAuthorizationStatus, to new: CLAuthorizationStatus) -> Bool {
        let allowed: (CLAuthorizationStatus) -> Bool = { $0 == .authorizedAlways || $0 == .authorizedWhenInUse }
        return allowed(new) && !allowed(old)
    }

    /// Makes no CoreLocation object: `start()` does, in the app. Tests pass
    /// their own conditions, store and status.
    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         route: @escaping () -> ActiveRouteStore = { .shared },
         makeSession: @escaping (CLServiceSession.AuthorizationRequirement) -> SiteSession = {
             CLServiceSession(authorization: $0)
         },
         conditions: SiteConditions? = nil,
         legacy: (any RegionMonitoring)? = nil,
         authorization: CLAuthorizationStatus = .notDetermined,
         accuracy: CLAccuracyAuthorization = .fullAccuracy) {
        self.defaults = defaults
        self.now = now
        self.route = route
        self.makeSession = makeSession
        self.conditions = conditions
        self.legacy = legacy
        self.authorization = authorization
        self.accuracy = accuracy
        placed = SiteEvents.load(from: defaults)
        super.init()
    }

    /// At launch, in the app only. Takes the service session at once if areas
    /// were placed before (iOS wants it retaken promptly after a background
    /// relaunch), then opens the monitor once protected data is available:
    /// iOS keeps a crossing until then.
    func start() {
        guard manager == nil else { return }
        let manager = CLLocationManager()
        self.manager = manager
        legacy = manager
        resume(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        manager.delegate = self
        // After launch, once UIKit's application exists.
        Task { openWhenProtectedDataAvailable() }
    }

    /// Location as last seen, then as now (a change made in Settings while
    /// PlowR wasn't running is a change too), and the session from what was
    /// placed before.
    func resume(status current: CLAuthorizationStatus, accuracy currentAccuracy: CLAccuracyAuthorization) {
        if let last = defaults.array(forKey: SiteEvents.accessKey) as? [Int], last.count == 2,
           let status = CLAuthorizationStatus(rawValue: Int32(last[0])),
           let lastAccuracy = CLAccuracyAuthorization(rawValue: last[1]) {
            authorization = status
            accuracy = lastAccuracy
        } else {
            authorization = current
            accuracy = currentAccuracy
        }
        authorizationChanged(to: current, accuracy: currentAccuracy)
        updateSession()
    }

    private func openWhenProtectedDataAvailable() {
        if UIApplication.shared.isProtectedDataAvailable {
            open()
            return
        }
        // Becoming active too, in case the unlock came while PlowR was suspended.
        for name in [UIApplication.protectedDataDidBecomeAvailableNotification,
                     UIApplication.didBecomeActiveNotification] {
            protectedDataObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.open() }
            })
        }
    }

    private func open() {
        for observer in protectedDataObservers { NotificationCenter.default.removeObserver(observer) }
        protectedDataObservers = []
        guard conditions == nil, !opening else { return }
        opening = true
        // Preferences may have been unreadable at launch (before the first
        // unlock after a restart): read again, or iOS's areas would look
        // like strays and be removed.
        if placed.isEmpty { placed = SiteEvents.load(from: defaults) }
        Task {
            let monitor = await CLMonitor(Self.monitorName)
            listen(to: monitor)
            conditions = MonitorConditions(monitor: monitor)
            opening = false
            apply()
        }
    }

    private func listen(to monitor: CLMonitor) {
        Task { [weak self] in
            do {
                for try await event in await monitor.events { self?.handle(event) }
            } catch {
                Self.log.error("Area events ended: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - SiteWatching

    func watch(_ areas: [SiteArea]) {
        wanted = areas
        updateSession()
        apply()
    }

    /// Waits until every change asked so far is made (for tests).
    func settled() async {
        await applying?.value
    }

    private func apply() {
        let previous = applying
        applying = Task {
            await previous?.value
            await reconcile()
        }
    }

    private func reconcile() async {
        guard let conditions else { return }
        if eraseOwed {
            eraseOwed = false
            for id in await conditions.identifiers() { await conditions.remove(id) }
        }
        guard let wanted else { return }
        // Left from PlowR 1.7: the wanted areas are placed here instead.
        if let legacy {
            for region in legacy.monitoredRegions { legacy.stopMonitoring(for: region) }
        }
        guard accuracy == .fullAccuracy else { return }
        var held = Set(await conditions.identifiers())
        if replaceAll {
            replaceAll = false
            for id in held { await conditions.remove(id) }
            held = []
            placed = []
        }
        // Lost by iOS (it couldn't keep its file, say): placed afresh below.
        placed.removeAll { !held.contains($0.id) }
        let plan = SiteArea.plan(placed: placed.map(\.area), wanted: wanted)
        // By identifier, which is how iOS knows an area. Any that isn't
        // PlowR's record of what it placed goes too.
        for id in held.subtracting(placed.map(\.id)).union(plan.stop) { await conditions.remove(id) }
        placed.removeAll { plan.stop.contains($0.id) }
        for area in plan.place {
            placed.append(PlacedSite(area, placedAt: now()))
            // Before iOS can answer, so its first answer is known as that.
            SiteEvents.save(placed, to: defaults)
            await conditions.add(area)
        }
        SiteEvents.save(placed, to: defaults)
        updateSession()
    }

    /// Holds a service session while any area is placed or wanted, and none
    /// otherwise: without one, iOS doesn't hand a backgrounded app with
    /// Always its area events.
    func updateSession() {
        let need = SiteEvents.sessionNeed(status: authorization,
                                          hasAreas: !placed.isEmpty || !(wanted ?? []).isEmpty)
        guard need != sessionNeed else { return }
        session?.invalidate()
        session = need.map { makeSession($0) }
        sessionNeed = need
    }

    // MARK: - SiteErasing

    /// Delete Account & Data: every area out of iOS's monitor (now, or once
    /// it opens), PlowR's record of them, and the session.
    func eraseAll() {
        wanted = []
        placed = []
        SiteEvents.save([], to: defaults)
        defaults.removeObject(forKey: SiteEvents.accessKey)
        eraseOwed = true
        accuracyLimited = false
        lastExit = nil
        updateSession()
        apply()
    }

    // MARK: - Events

    func handle(_ event: some SiteEvent) {
        switch SiteEvents.reading(state: event.state, diagnostics: event) {
        case .limited(let limits): noteLimits(limits, id: event.identifier)
        case .presence(let presence): receive(event.identifier, presence: presence, at: event.date)
        case .nothing: break
        }
    }

    /// An event saying why an area isn't watched: not a crossing. Where the
    /// phone goes meanwhile isn't known, so the area's next answer is a first
    /// answer, and its next "inside" no arrival (`afterGap`). Logged, for a
    /// stop whose times weren't caught. The ID is a stop's UUID; nothing about
    /// the client.
    func noteLimits(_ limits: [SiteLimit], id: String) {
        for limit in limits {
            Self.log.error("Area \(id, privacy: .public) not watched: \(limit.rawValue, privacy: .public)")
        }
        if limits.contains(.accuracyLimited) { accuracyLimited = true }
        // Asking the user isn't a gap: iOS is still watching.
        guard limits != [.authorizationRequestInProgress],
              let index = placed.firstIndex(where: { $0.id == id }) else { return }
        placed[index].presence = .unknown
        placed[index].afterGap = true
        SiteEvents.save(placed, to: defaults)
    }

    /// iOS says the phone is `presence` for the area `id`, as of `date`.
    func receive(_ id: String, presence: SitePresence, at date: Date) {
        accuracyLimited = false
        // One from before this placement (an area moved, placed again under
        // the same ID) isn't about it.
        guard let index = placed.firstIndex(where: { $0.id == id }), date >= placed[index].placedAt else { return }
        let crossing = SiteEvents.crossing(previous: placed[index].presence, placedAt: placed[index].placedAt,
                                           afterGap: placed[index].afterGap ?? false, presence: presence, at: date)
        placed[index].presence = presence
        if presence != .unknown { placed[index].afterGap = nil }
        SiteEvents.save(placed, to: defaults)
        let store = route()
        switch crossing {
        case .entered(let time):
            store.siteEntered(id, at: time)
        case .exited(let time):
            let isCurrentStop = store.currentStopID?.uuidString == id
            store.siteExited(id, at: time)
            if isCurrentStop { lastExit = Exit(stopID: id, time: time) }
        case .insideWhenPlaced(let time):
            store.siteInsideWhenPlaced(id, at: time)
        case .none:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let newAccuracy = manager.accuracyAuthorization
        DispatchQueue.main.async { [weak self] in
            self?.authorizationChanged(to: status, accuracy: newAccuracy)
        }
    }

    func authorizationChanged(to status: CLAuthorizationStatus, accuracy newAccuracy: CLAccuracyAuthorization) {
        // Allowed only now: iOS starts working out where the phone is only
        // now, and the crew may have driven in meanwhile, so its next
        // "inside" for each area is no arrival (`afterGap`). Not on every
        // launch: a relaunch for an arrival would lose it.
        if Self.isNewlyAllowed(from: authorization, to: status) {
            for index in placed.indices {
                placed[index].presence = .unknown
                placed[index].afterGap = true
            }
            SiteEvents.save(placed, to: defaults)
        }
        // Only when changed: a launch before the first unlock after a restart
        // can't read preferences, and needn't write them.
        let access = [Int(status.rawValue), newAccuracy.rawValue]
        if defaults.array(forKey: SiteEvents.accessKey) as? [Int] != access {
            defaults.set(access, forKey: SiteEvents.accessKey)
        }
        authorization = status
        if accuracy == .reducedAccuracy, newAccuracy == .fullAccuracy { replaceAll = true }
        if newAccuracy == .fullAccuracy { accuracyLimited = false }
        accuracy = newAccuracy
        updateSession()
        if wanted != nil { apply() }
    }

    private static let log = Logger(subsystem: "Scoops.PlowR", category: "SiteMonitor")
}

/// The areas iOS watches for PlowR: its `CLMonitor` in the app, a fake in tests.
protocol SiteConditions: AnyObject {
    func identifiers() async -> [String]
    /// Placed with its state unknown, never assumed (`SiteEvents.crossing`).
    func add(_ area: SiteArea) async
    func remove(_ id: String) async
}

final class MonitorConditions: SiteConditions {
    private let monitor: CLMonitor

    init(monitor: CLMonitor) {
        self.monitor = monitor
    }

    func identifiers() async -> [String] {
        await monitor.identifiers
    }

    func add(_ area: SiteArea) async {
        let condition = CLMonitor.CircularGeographicCondition(
            center: CLLocationCoordinate2D(latitude: area.latitude, longitude: area.longitude),
            radius: SiteMonitor.radius)
        await monitor.add(condition, identifier: area.id)
    }

    func remove(_ id: String) async {
        await monitor.remove(id)
    }
}

/// A service session, held while areas are watched.
protocol SiteSession: AnyObject {
    func invalidate()
}

extension CLServiceSession: SiteSession {}

/// What Delete Account & Data clears of the job-site areas.
protocol SiteErasing {
    func eraseAll()
}

/// `SiteMonitor`, except under tests: the test host is the app, and mustn't
/// place areas on the simulator.
struct SystemSiteWatching: SiteWatching {
    func watch(_ areas: [SiteArea]) {
        guard !PlowRApp.isRunningUnderTests else { return }
        // A Mac isn't on the route (OnMac): no job-site areas there.
        SiteMonitor.shared.watch(OnMac.isMac ? [] : areas)
    }
}
