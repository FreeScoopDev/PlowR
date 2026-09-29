import Foundation

/// What an event for a visit says.
struct EventDetails: Equatable {
    var title: String
    var location: String
    var notes: String
    var start: Date
    var end: Date
    /// The reminder an hour before. Only a visit still to do has one.
    var hasReminder: Bool

    /// The same, as far as the calendar can tell: text as iCloud may give it
    /// back (other line endings, spaces trimmed), so a round trip through
    /// the calendar doesn't look like a change and rewrite the event on
    /// every sync.
    func matches(_ other: EventDetails) -> Bool {
        func tidy(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tidy(title) == tidy(other.title) && tidy(location) == tidy(other.location)
            && tidy(notes) == tidy(other.notes) && start == other.start && end == other.end
            && hasReminder == other.hasReminder
    }
}

/// An event in a "PlowR" calendar, as `VisitCalendarStore` reads it.
struct CalendarEvent: Equatable {
    var id: String
    /// The visit it's for, from its `plowr://visit/<id>` link. Nil for an
    /// event PlowR didn't add, which it never changes.
    var visitID: UUID?
    var details: EventDetails
    var created: Date?
    /// The same on every device the calendar syncs to, unlike `id`.
    var sharedID: String?
}

enum CalendarChange: Equatable {
    case add(visitID: UUID, EventDetails)
    case update(eventID: String, EventDetails)
    case remove(eventID: String)
}

/// Whether PlowR may use the calendar. Only full access can find the events
/// it added again. Write-only access, which earlier versions asked for, can't
/// read events back or make a calendar.
enum CalendarAccess: Equatable {
    case full
    /// Not asked yet, or only write-only granted: asking shows a prompt.
    case canAsk
    /// Denied or restricted: only the Settings app can change it.
    case denied
}

/// The "PlowR" calendar: EventKit in the app (`EventKitVisitCalendarStore`),
/// a fake in tests.
///
/// There can be more than one: two devices turning sync on before iCloud has
/// brought either one's calendar to the other. They're treated as one: events
/// are read from all of them and new ones go in the first.
@MainActor
protocol VisitCalendarStore: AnyObject {
    var access: CalendarAccess { get }
    /// PlowR made or found a calendar on this device and hasn't removed it.
    var remembersCalendar: Bool { get }
    /// Asks for full access. True when it's granted.
    func requestFullAccess() async -> Bool
    /// The PlowR calendars' events in `span`, making a calendar first when
    /// `create` is true and there's none. Nil when there's no PlowR calendar
    /// and `create` is false.
    func events(in span: DateInterval, create: Bool) throws -> [CalendarEvent]?
    /// All of them or none.
    func apply(_ changes: [CalendarChange]) throws
    /// Removes each PlowR calendar that has no events left in any of `spans`.
    func removeEmptyCalendars(searching spans: [DateInterval]) throws
}

/// How the "PlowR" calendar should look for the schedule, and the changes
/// that get it there. `CalendarSync` runs it (Settings > Add Visits to
/// Calendar).
///
/// An event is matched to its visit by the `plowr://visit/<id>` link it
/// carries, not by an event ID kept on the visit: the visit syncs to the
/// user's other devices, and an event's ID is only good on the device that
/// made it. The calendar can be on those devices too (an iCloud calendar),
/// so an event whose visit this device hasn't received yet is left alone.
/// Only one for a visit this device has had, and that's now gone, is removed.
enum VisitCalendar {
    /// A visit with no estimated duration takes an hour in the calendar.
    static let defaultMinutes = 60
    /// When the reminder goes off, from the visit's start.
    static let reminderOffset: TimeInterval = -3600

    /// The visits that have events: from a month ago up to (not including)
    /// six months ahead. A repeating visit is scheduled two years ahead, and
    /// events for all of it would crowd the calendar; the rest are added as
    /// the window moves on.
    static func window(from now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .month, value: -1, to: today) ?? today
        let end = calendar.date(byAdding: .month, value: 6, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    /// In `window`, which excludes its end. A calendar search leaves out an
    /// event that starts right at the end, so a visit there would be added
    /// again on every sync.
    static func isIn(_ window: DateInterval, _ date: Date) -> Bool {
        window.start <= date && date < window.end
    }

    /// Every year an event PlowR added could be in, in three-year spans:
    /// EventKit searches at most four years at a time. To remove them all,
    /// and to know a calendar holds nothing else before removing it.
    static let allTime: [DateInterval] = {
        let span: TimeInterval = 3 * 365 * 86_400
        var spans: [DateInterval] = []
        var start = Date(timeIntervalSinceReferenceDate: 599_529_600)            // 2020-01-01
        let end = Date(timeIntervalSinceReferenceDate: 3_124_137_600)            // 2100-01-01
        while start < end {
            let next = min(start.addingTimeInterval(span), end)
            spans.append(DateInterval(start: start, end: next))
            start = next
        }
        return spans
    }()

    static func link(for visitID: UUID) -> URL? {
        URL(string: "plowr://visit/\(visitID.uuidString)")
    }

    static func visitID(fromLink url: URL?) -> UUID? {
        guard let url, url.scheme == "plowr", url.host == "visit" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// What `visit`'s event says, or nil when it shouldn't have one: a
    /// skipped or cancelled visit isn't happening. A completed one keeps its
    /// event as a record, without the reminder.
    static func details(for visit: ScheduledVisit) -> EventDetails? {
        guard visit.status == .scheduled || visit.status == .completed else { return nil }
        // To the minute, as the calendar shows it. A visit added for "now"
        // carries seconds, and a calendar that doesn't keep them would look
        // changed on every sync.
        let minute = (visit.scheduledDate.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        let start = Date(timeIntervalSinceReferenceDate: minute)
        let minutes = visit.estimatedMinutes > 0 ? visit.estimatedMinutes : defaultMinutes
        return EventDetails(title: "PlowR: \(visit.clientName)", location: visit.clientAddress,
                            notes: visit.notes, start: start,
                            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                            hasReminder: visit.status == .scheduled)
    }

    /// The changes that bring `events` in step with the schedule.
    /// - Parameters:
    ///   - visits: every visit dated in `window`, whoever's, and any other
    ///     visit one of `events` is for.
    ///   - operatorID: the signed-in business. Only its visits get events.
    ///   - events: the PlowR calendars' events in `window`.
    ///   - seen: the visits this device had at the last sync (`seen(...)`).
    static func changes(visits: [ScheduledVisit], operatorID: String, events: [CalendarEvent],
                        seen: Set<UUID>, window: DateInterval) -> [CalendarChange] {
        var wanted: [UUID: EventDetails] = [:]
        for visit in visits where visit.operatorID == operatorID && isIn(window, visit.scheduledDate) {
            wanted[visit.id] = details(for: visit)
        }
        let known = Set(visits.map(\.id))
        var changes: [CalendarChange] = []
        var matched: Set<UUID> = []
        // Oldest first, so of two events for one visit (two devices adding it
        // at the same time) every device keeps the same one. A tie goes by the
        // ID every device shares, not this device's own.
        let oldestFirst = events.sorted {
            ($0.created ?? .distantFuture, $0.sharedID ?? $0.id) < ($1.created ?? .distantFuture, $1.sharedID ?? $1.id)
        }
        for event in oldestFirst {
            guard let visitID = event.visitID else { continue }
            if let details = wanted[visitID], matched.insert(visitID).inserted {
                if !event.details.matches(details) { changes.append(.update(eventID: event.id, details)) }
            } else if wanted[visitID] != nil {
                changes.append(.remove(eventID: event.id))      // a second event for the visit
            } else if event.details.start < window.start {
                // Begun before the window (say an overnight run): a record,
                // like every event the window has moved past.
            } else if known.contains(visitID) || seen.contains(visitID) {
                // Skipped, cancelled, moved out of the window or another
                // business's; or deleted.
                changes.append(.remove(eventID: event.id))
            }
            // Otherwise the visit is one this device hasn't received yet.
        }
        let adds = wanted.filter { !matched.contains($0.key) }
            .sorted { ($0.value.start, $0.key.uuidString) < ($1.value.start, $1.key.uuidString) }
        return changes + adds.map { .add(visitID: $0.key, $0.value) }
    }

    /// The visits to count as seen at the next sync: every one dated in the
    /// window, and any seen before whose event was still there, in case
    /// removing it didn't take.
    static func seen(visits: [ScheduledVisit], events: [CalendarEvent], before: Set<UUID>,
                     window: DateInterval) -> Set<UUID> {
        let dated = visits.filter { isIn(window, $0.scheduledDate) }.map(\.id)
        return Set(dated).union(before.intersection(events.compactMap(\.visitID)))
    }
}
