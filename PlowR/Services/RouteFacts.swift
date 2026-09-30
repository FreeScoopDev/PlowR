import Foundation

/// What the route list and a route's page say about a route beyond its stops:
/// roughly how long it takes, and when it last ran. Worked out here once so
/// the two screens can't disagree.
enum RouteFacts {
    /// About how long the route's work takes: each client stop's client's
    /// average time on site, for those with one. Travel isn't included.
    static func estimatedMinutes(of stops: [RouteStop], clients: [Client]) -> Int {
        let byID = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return stops.reduce(0) { total, stop in
            guard !stop.isCustomStop, let client = byID[stop.clientID], client.averageServiceMinutes > 0 else {
                return total
            }
            return total + Int(client.averageServiceMinutes.rounded())
        }
    }

    /// A stop's target time: its own (set on its page, or from the client's
    /// goal when the route was built), or else the client's goal now. 0: none.
    static func targetMinutes(of stop: RouteStop, client: Client?) -> Int {
        if stop.targetMinutes > 0 { return stop.targetMinutes }
        guard let client else { return 0 }
        return Place.of(client, propertyID: stop.propertyID)?.goalMinutes ?? 0
    }

    /// One service the route needs, and at how many stops.
    struct LoadOutLine: Equatable {
        let name: String
        let stops: Int
    }

    /// What a route's stops are expected to need, service by service, in the
    /// catalog's order: what to load before heading out. Only services still
    /// in the active catalog (`services`).
    static func loadOut(of stops: [RouteStop], clients: [Client],
                        services: [StopRecording.Service]) -> [LoadOutLine] {
        let byID = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        for stop in stops {
            let client = stop.isCustomStop ? nil : byID[stop.clientID]
            for id in Set(StopServices.expected(for: stop, client: client)) { counts[id, default: 0] += 1 }
        }
        return services.compactMap { service in
            counts[service.id].map { LoadOutLine(name: service.name, stops: $0) }
        }
    }

    /// "45m", "2h", "1h 20m".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "Last run today", "… 2 days ago", or the date once it's over a week.
    static func lastRunText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Last run today"
        case 1: return "Last run yesterday"
        case 2...6: return "Last run \(days) days ago"
        default: return "Last run \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    /// When the route last did any work: the latest stop it completed, from
    /// the Service Log. nil if it has never run (since the log existed).
    static func lastRun(of routeID: UUID, in records: [ServiceRecord]) -> Date? {
        let id = routeID.uuidString
        return records.filter { $0.routeID == id && $0.startedAt != nil }.map(\.performedAt).max()
    }

    /// The last run of every route in `records`, by route ID, in one pass.
    static func lastRuns(in records: [ServiceRecord]) -> [String: Date] {
        var latest: [String: Date] = [:]
        for record in records where !record.routeID.isEmpty && record.startedAt != nil {
            if let seen = latest[record.routeID], seen >= record.performedAt { continue }
            latest[record.routeID] = record.performedAt
        }
        return latest
    }
}
