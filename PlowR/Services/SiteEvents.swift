import CoreLocation
import Foundation

/// Where the phone is, for one job-site area, as PlowR last heard from iOS.
/// `unknown` from placing the area until iOS first says.
enum SitePresence: String, Codable {
    case unknown, inside, outside
}

/// What one of iOS's events for an area means.
enum SiteCrossing: Equatable {
    /// Came into the area at this time: a crossing iOS saw.
    case entered(Date)
    /// Went out of it.
    case exited(Date)
    /// Already inside when the area was placed: no arrival was seen.
    case insideWhenPlaced(Date)
    case none
}

/// An area placed in the monitor, as PlowR keeps it across launches (iOS
/// keeps the area itself): where, when it was placed, and where the phone
/// was last heard to be.
struct PlacedSite: Codable, Equatable {
    var id: String
    var latitude: Double
    var longitude: Double
    var placedAt: Date
    var presence: SitePresence = .unknown
    /// iOS stopped watching it for a while (location off or approximate, not
    /// in use): where the phone went meanwhile isn't known, so its next
    /// "inside" is no arrival, however late. nil in a record from before.
    var afterGap: Bool?

    init(_ area: SiteArea, placedAt: Date) {
        id = area.id
        latitude = area.latitude
        longitude = area.longitude
        self.placedAt = placedAt
    }

    var area: SiteArea { SiteArea(id: id, latitude: latitude, longitude: longitude) }
}

/// Why iOS isn't watching an area, from the diagnostics on an event (iOS 18).
enum SiteLimit: String, CaseIterable {
    /// Precise Location is off: iOS watches no areas (RouteGPS.needsPrecise).
    case accuracyLimited
    case conditionLimitExceeded
    case conditionUnsupported
    case authorizationDenied
    case authorizationDeniedGlobally
    case authorizationRestricted
    case persistenceUnavailable
    case serviceSessionRequired
    case insufficientlyInUse
    case authorizationRequestInProgress
}

/// The diagnostics iOS 18 puts on a monitor event: a protocol so a test can
/// make one (iOS makes the events).
protocol SiteDiagnostics {
    var accuracyLimited: Bool { get }
    var conditionLimitExceeded: Bool { get }
    var conditionUnsupported: Bool { get }
    var authorizationDenied: Bool { get }
    var authorizationDeniedGlobally: Bool { get }
    var authorizationRestricted: Bool { get }
    var persistenceUnavailable: Bool { get }
    var serviceSessionRequired: Bool { get }
    var insufficientlyInUse: Bool { get }
    var authorizationRequestInProgress: Bool { get }
}

extension CLMonitor.Event: SiteDiagnostics {}

/// The rules for turning iOS's area events into arrivals and departures, kept
/// apart from CoreLocation's monitor so they can be tested.
enum SiteEvents {
    /// The phone's place from an event's state; nil when iOS doesn't know
    /// (`unknown`) or no longer watches the area (`unmonitored`).
    static func presence(of state: CLMonitor.Event.State) -> SitePresence? {
        switch state {
        case .satisfied: .inside
        case .unsatisfied: .outside
        default: nil
        }
    }

    /// What iOS saying the phone is now `presence`, at `date`, means for an
    /// area last heard at `previous` and placed at `placedAt`.
    ///
    /// The first state after placing is iOS working out where the phone is,
    /// not a crossing: inside is "already there", and outside means the next
    /// inside is a real arrival, however soon. Areas are placed with their
    /// state unknown (`add(_:identifier:)`, not `assuming:`) for this: an
    /// assumed state would make that first answer look like a crossing.
    /// iOS may not answer until the phone actually crosses, so a first
    /// inside `SiteTimes.settleTime` or more after placing is taken as the
    /// arrival, as legacy monitoring did.
    /// After a gap in iOS's watching (`afterGap`), a first "inside" is never
    /// an arrival: the crew may have driven in while nothing watched.
    static func crossing(previous: SitePresence, placedAt: Date, afterGap: Bool = false, presence: SitePresence,
                         at date: Date) -> SiteCrossing {
        guard presence != previous, presence != .unknown else { return .none }
        switch (previous, presence) {
        case (.unknown, .inside):
            return afterGap || date.timeIntervalSince(placedAt) < SiteTimes.settleTime
                ? .insideWhenPlaced(date) : .entered(date)
        case (.unknown, .outside):
            return .none
        case (_, .inside):
            return .entered(date)
        default:
            return .exited(date)
        }
    }

    /// What an event says: why iOS isn't watching (diagnostics come first: an
    /// event carrying any is never a crossing), where the phone is, or
    /// nothing (unknown, unmonitored).
    enum Reading: Equatable {
        case limited([SiteLimit])
        case presence(SitePresence)
        case nothing
    }

    static func reading(state: CLMonitor.Event.State, diagnostics: some SiteDiagnostics) -> Reading {
        let limits = limits(of: diagnostics)
        if !limits.isEmpty { return .limited(limits) }
        return presence(of: state).map { .presence($0) } ?? .nothing
    }

    /// The diagnostics set on an event. Any means it's about iOS's watching,
    /// not the phone: not a crossing.
    static func limits(of event: some SiteDiagnostics) -> [SiteLimit] {
        let flags: [(Bool, SiteLimit)] = [
            (event.accuracyLimited, .accuracyLimited),
            (event.conditionLimitExceeded, .conditionLimitExceeded),
            (event.conditionUnsupported, .conditionUnsupported),
            (event.authorizationDenied, .authorizationDenied),
            (event.authorizationDeniedGlobally, .authorizationDeniedGlobally),
            (event.authorizationRestricted, .authorizationRestricted),
            (event.persistenceUnavailable, .persistenceUnavailable),
            (event.serviceSessionRequired, .serviceSessionRequired),
            (event.insufficientlyInUse, .insufficientlyInUse),
            (event.authorizationRequestInProgress, .authorizationRequestInProgress)
        ]
        return flags.filter(\.0).map(\.1)
    }

    /// The service session to hold: iOS hands a backgrounded app with Always
    /// no area events without one. Only while areas are placed or wanted,
    /// and only at the level already allowed, so holding one never asks the
    /// user for anything.
    static func sessionNeed(status: CLAuthorizationStatus, hasAreas: Bool) -> CLServiceSession.AuthorizationRequirement? {
        guard hasAreas else { return nil }
        switch status {
        case .authorizedAlways: return .always
        case .authorizedWhenInUse: return .whenInUse
        default: return nil
        }
    }

    static let placedKey = "siteAreasPlaced"
    /// Location's status and accuracy when last seen, so a change made while
    /// PlowR wasn't running is seen at the next launch.
    static let accessKey = "siteAreasAccess"

    static func load(from defaults: UserDefaults) -> [PlacedSite] {
        guard let data = defaults.data(forKey: placedKey) else { return [] }
        return (try? JSONDecoder().decode([PlacedSite].self, from: data)) ?? []
    }

    static func save(_ placed: [PlacedSite], to defaults: UserDefaults) {
        if placed.isEmpty {
            defaults.removeObject(forKey: placedKey)
        } else if let data = try? JSONEncoder().encode(placed) {
            defaults.set(data, forKey: placedKey)
        }
    }
}
