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

    /// The last area the phone went out of, for the route screen's offer to
    /// text the next client.
    var lastExitedRegionID: String?

    private let manager = CLLocationManager()
    /// What the route wants watched, placed again once location is allowed.
    /// nil until the route has said: iOS keeps areas across launches, and
    /// they mustn't be cleared before the route is restored.
    private var wanted: [SiteArea]?

    override private init() {
        super.init()
        manager.delegate = self
    }

    func watch(_ areas: [SiteArea]) {
        wanted = areas
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let placed = manager.monitoredRegions.compactMap { $0 as? CLCircularRegion }
        for region in placed where !areas.contains(where: { Self.matches(region, $0) }) {
            manager.stopMonitoring(for: region)
        }
        for area in areas where !placed.contains(where: { Self.matches($0, area) }) {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: area.latitude,
                                                                         longitude: area.longitude),
                                          radius: Self.radius, identifier: area.id)
            region.notifyOnEntry = true        // a completed stop's entry drops its departure
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    /// Placed already, where the area is now (its pin can move with the client's).
    private static func matches(_ region: CLCircularRegion, _ area: SiteArea) -> Bool {
        region.identifier == area.id
            && abs(region.center.latitude - area.latitude) < 1e-7
            && abs(region.center.longitude - area.longitude) < 1e-7
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let wanted else { return }
            watch(wanted)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let time = Date()
        DispatchQueue.main.async {
            ActiveRouteStore.shared.siteEntered(region.identifier, at: time)
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let time = Date()
        DispatchQueue.main.async { [weak self] in
            ActiveRouteStore.shared.siteExited(region.identifier, at: time)
            self?.lastExitedRegionID = region.identifier
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
