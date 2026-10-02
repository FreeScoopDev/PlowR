import CoreLocation
import Foundation

/// The app's one keeper of job-site areas: the current stop's, for arrival
/// and departure, and completed stops' still waiting on a departure.
///
/// Made at launch (`PlowRApp.init`), not by a screen: iOS relaunches PlowR in
/// the background when the phone crosses an area, and hands the crossing to
/// whatever location manager exists then. `ActiveRouteStore` decides what is
/// watched and what a crossing means; this only places the areas and passes
/// crossings on.
@Observable
final class SiteMonitor: NSObject, CLLocationManagerDelegate, SiteWatching {
    static let shared = SiteMonitor()

    /// About a property's size; also iOS's practical minimum.
    static let radius: CLLocationDistance = 100

    /// The phone went out of the current stop's area: for the route screen's
    /// offer to text the next client. Each exit is a new value, so one left
    /// over from an exit the screen wasn't up for can't hide the next from
    /// `onChange`.
    struct Exit: Equatable {
        var stopID: String
        var token = UUID()
    }
    var lastExit: Exit?

    private let manager = CLLocationManager()
    /// What the route wants watched, placed again once location is allowed.
    /// nil until the route has said: iOS keeps areas across launches, and
    /// they mustn't be cleared before the route is restored.
    private var wanted: [SiteArea]?
    /// What's placed, kept here rather than read back from iOS (whose copy
    /// may lag, or round a centre). At launch, the areas iOS kept from before,
    /// if they're this version's kind; any other is stopped on the first watch.
    private var placed: [SiteArea] = []
    private var stale: [CLRegion] = []
    /// When each area was placed, this launch. An entry soon after isn't an
    /// arrival (`SiteTimes.settleTime`).
    private var placedAt: [String: Date] = [:]
    /// The status last seen. iOS calls the authorization callback when the
    /// manager is made too, with nothing changed.
    private var authorization: CLAuthorizationStatus

    /// Whether going from `old` to `new` means location was allowed only now.
    static func isNewlyAllowed(from old: CLAuthorizationStatus, to new: CLAuthorizationStatus) -> Bool {
        let allowed: (CLAuthorizationStatus) -> Bool = { $0 == .authorizedAlways || $0 == .authorizedWhenInUse }
        return allowed(new) && !allowed(old)
    }

    override private init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        for region in manager.monitoredRegions {
            if let circle = region as? CLCircularRegion, circle.radius == Self.radius,
               circle.notifyOnEntry, circle.notifyOnExit {
                placed.append(SiteArea(id: circle.identifier, latitude: circle.center.latitude,
                                       longitude: circle.center.longitude))
            } else {
                stale.append(region)
            }
        }
    }

    func watch(_ areas: [SiteArea]) {
        wanted = areas
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in stale { manager.stopMonitoring(for: region) }
        stale = []
        // A kept area whose centre came back from iOS a hair off is the same area.
        placed = placed.map { area in
            areas.first { $0.id == area.id && abs($0.latitude - area.latitude) < 1e-7
                && abs($0.longitude - area.longitude) < 1e-7 } ?? area
        }
        let plan = SiteArea.plan(placed: placed, wanted: areas)
        // By identifier, which is how iOS matches a stop: its own list of
        // what's watched may not show an area placed moments ago.
        for area in placed where plan.stop.contains(area.id) {
            manager.stopMonitoring(for: CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: area.latitude, longitude: area.longitude),
                radius: Self.radius, identifier: area.id))
        }
        for area in plan.place {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: area.latitude,
                                                                         longitude: area.longitude),
                                          radius: Self.radius, identifier: area.id)
            region.notifyOnEntry = true        // a completed stop's entry drops its departure
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            placedAt[area.id] = Date()
        }
        placed = areas
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Allowed only now: iOS starts working out where the phone is
            // only now, so an entry it reports next may not be an arrival.
            // Not on every launch: a relaunch for an arrival would lose it.
            if Self.isNewlyAllowed(from: authorization, to: status) {
                for area in placed { placedAt[area.id] = Date() }
            }
            authorization = status
            if let wanted { watch(wanted) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let time = Date()
        DispatchQueue.main.async { [weak self] in
            let placedAt = self?.placedAt[region.identifier]
            ActiveRouteStore.shared.siteEntered(region.identifier, at: time, placedAt: placedAt)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let time = Date()
        DispatchQueue.main.async { [weak self] in
            let store = ActiveRouteStore.shared
            let isCurrentStop = store.currentStopID?.uuidString == region.identifier
            store.siteExited(region.identifier, at: time)
            if isCurrentStop { self?.lastExit = Exit(stopID: region.identifier) }
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Not fatal: the stop is completed by hand, and its times are the route's.
    }
}

/// `SiteMonitor`, except under tests: the test host is the app, and mustn't
/// place areas on the simulator.
struct SystemSiteWatching: SiteWatching {
    func watch(_ areas: [SiteArea]) {
        guard !PlowRApp.isRunningUnderTests else { return }
        SiteMonitor.shared.watch(areas)
    }
}
