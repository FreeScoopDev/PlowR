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
