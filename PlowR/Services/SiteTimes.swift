import CoreLocation
import Foundation

/// When the crew got to the current stop and left it, as GPS saw it: the
/// phone crossing an area about 100 m around the stop's pin (`SiteMonitor`).
/// Kept with the route's checkpoint, so it survives the app being ended,
/// and copied onto the stop's Service Log record when the stop is completed.
///
/// Only what was seen is kept. A crew already inside the area when the stop
/// began (the next house along) never crosses into it, so it has no arrival,
/// and none is made up: the report says arrival wasn't caught.
struct SiteTimes: Codable, Equatable {
    /// The first time the phone came into the area after the stop began.
    var arrivedAt: Date?
    /// The last time it went out, unless it came back in since.
    var leftAt: Date?
    /// No arrival can be given: the phone was inside the area too soon after
    /// the stop began to have driven there, or went out of it without having
    /// been seen to come in. A later entry isn't the arrival either.
    var arrivalUnseen = false

    /// An entry this soon after the stop began, or after its area was placed
    /// (again: its pin moved, or location was allowed only then), isn't an
    /// arrival: iOS can report a phone already inside an area once it's placed.
    static let settleTime: TimeInterval = 60

    /// `settleFrom`: the later of when the stop began and when its area was
    /// last placed.
    mutating func entered(at time: Date, settleFrom: Date) {
        leftAt = nil        // Back in: going out wasn't leaving.
        guard arrivedAt == nil, !arrivalUnseen else { return }
        if time.timeIntervalSince(settleFrom) < Self.settleTime {
            arrivalUnseen = true
        } else {
            arrivedAt = time
        }
    }

    mutating func exited(at time: Date) {
        if arrivedAt == nil { arrivalUnseen = true }
        leftAt = time
    }
}

/// A completed stop whose departure hasn't been seen yet: no exit since the
/// phone was last seen in its area, or none seen at all (already inside when
/// its area was placed). Watched until the phone leaves the area. Not after
/// `SiteDepartures.window` (driving by days later isn't leaving), and not
/// once the phone is seen coming in (it wasn't there when the stop was
/// completed, so a later exit isn't leaving it), once the phone is seen in
/// a later stop's area or a later stop is completed or passed (the crew was
/// there, so they'd left this one), or
/// when the current stop's area overlaps it (leaving the current stop would
/// also go out of this one's). Kept apart from the route, so the last stop's
/// departure is still caught after End Route.
struct PendingDeparture: Codable, Equatable {
    var runID: UUID
    var stopID: UUID
    var completedAt: Date
    var latitude: Double
    var longitude: Double
}

enum SiteDepartures {
    static let key = "siteDepartures"
    /// How long after completing a stop a departure from it still counts.
    static let window: TimeInterval = 2 * 60 * 60

    static func load(from defaults: UserDefaults) -> [PendingDeparture] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingDeparture].self, from: data)) ?? []
    }

    static func save(_ pending: [PendingDeparture], to defaults: UserDefaults) {
        if pending.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: key)
        }
    }

    /// Those still within their window: at most the newest, as only the
    /// last stop moved on from is awaited (a list saved by an older version
    /// could hold several).
    static func current(_ pending: [PendingDeparture], now: Date) -> [PendingDeparture] {
        Array(pending.filter { now.timeIntervalSince($0.completedAt) <= window }.suffix(1))
    }

    /// Whether the pending stop's area and an area centred here overlap.
    static func overlaps(_ pending: PendingDeparture, latitude: Double, longitude: Double) -> Bool {
        let distance = CLLocation(latitude: pending.latitude, longitude: pending.longitude)
            .distance(from: CLLocation(latitude: latitude, longitude: longitude))
        return distance < 2 * SiteMonitor.radius
    }
}

/// An area around a stop for iOS to watch.
struct SiteArea: Equatable {
    var id: String
    var latitude: Double
    var longitude: Double

    /// What to change to watch `wanted` when `placed` are watched: areas to
    /// stop (gone, or moved) and areas to place. Those placed already, where
    /// they are now, are left alone: placing one afresh makes iOS work out
    /// again whether the phone is inside it.
    static func plan(placed: [SiteArea], wanted: [SiteArea]) -> (stop: [String], place: [SiteArea]) {
        (placed.filter { !wanted.contains($0) }.map(\.id), wanted.filter { !placed.contains($0) })
    }
}

/// What watches the areas: `SiteMonitor` in the app, nothing in tests.
protocol SiteWatching {
    /// Watches exactly these areas, leaving any already placed as they are:
    /// an area placed afresh first has to work out whether the phone is in it.
    func watch(_ areas: [SiteArea])
}

struct NoSiteWatching: SiteWatching {
    func watch(_ areas: [SiteArea]) {}
}
