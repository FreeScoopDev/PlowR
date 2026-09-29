import EventKit
import UIKit

/// The "PlowR" calendar, through EventKit. Only reads and changes PlowR's
/// calendars; `VisitCalendar` decides what goes in them.
final class EventKitVisitCalendarStore: VisitCalendarStore {
    static let calendarTitle = "PlowR"
    /// The calendar PlowR made or found, so renaming it in Calendar doesn't
    /// lose it.
    static let calendarIDKey = "calendarSyncCalendarID"

    private let store = EKEventStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .full
        case .notDetermined, .writeOnly: return .canAsk
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    var remembersCalendar: Bool { defaults.string(forKey: Self.calendarIDKey) != nil }

    func requestFullAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// iCloud or this device: the privacy policy says client details stay
    /// on the device and in iCloud. Never a Google or Exchange calendar, even
    /// one named "PlowR".
    nonisolated static func isOwnAccount(type: EKSourceType, title: String) -> Bool {
        type == .local || (type == .calDAV && title == "iCloud")
    }

    func events(in span: DateInterval, create: Bool) throws -> [CalendarEvent]? {
        var calendars = plowRCalendars()
        if calendars.isEmpty {
            guard create else { return nil }
            calendars = [try newCalendar()]
        }
        let predicate = store.predicateForEvents(withStart: span.start, end: span.end, calendars: calendars)
        return store.events(matching: predicate).map { event in
            let reminder = event.alarms?.contains { $0.relativeOffset == VisitCalendar.reminderOffset } ?? false
            let details = EventDetails(title: event.title ?? "", location: event.location ?? "",
                                       notes: event.notes ?? "", start: event.startDate, end: event.endDate,
                                       hasReminder: reminder)
            return CalendarEvent(id: event.calendarItemIdentifier, visitID: VisitCalendar.visitID(fromLink: event.url),
                                 details: details, created: event.creationDate,
                                 sharedID: event.calendarItemExternalIdentifier)
        }
    }

    func apply(_ changes: [CalendarChange]) throws {
        guard !changes.isEmpty else { return }
        let calendar = try plowRCalendars().first ?? newCalendar()
        do {
            for change in changes {
                switch change {
                case let .add(visitID, details):
                    let event = EKEvent(eventStore: store)
                    event.calendar = calendar
                    event.url = VisitCalendar.link(for: visitID)
                    Self.write(details, to: event)
                    try store.save(event, span: .thisEvent, commit: false)
                case let .update(eventID, details):
                    guard let event = store.calendarItem(withIdentifier: eventID) as? EKEvent else { continue }
                    Self.write(details, to: event)
                    try store.save(event, span: .thisEvent, commit: false)
                case let .remove(eventID):
                    guard let event = store.calendarItem(withIdentifier: eventID) as? EKEvent else { continue }
                    try store.remove(event, span: .thisEvent, commit: false)
                }
            }
            try store.commit()
        } catch {
            // Nothing half done: the next sync starts again from what's saved.
            store.reset()
            throw error
        }
    }

    func removeEmptyCalendars(searching spans: [DateInterval]) throws {
        for calendar in plowRCalendars() {
            let empty = spans.allSatisfy { span in
                store.events(matching: store.predicateForEvents(withStart: span.start, end: span.end,
                                                                 calendars: [calendar])).isEmpty
            }
            guard empty else { continue }
            try store.removeCalendar(calendar, commit: true)
        }
        if plowRCalendars().isEmpty { defaults.removeObject(forKey: Self.calendarIDKey) }
    }

    private static func write(_ details: EventDetails, to event: EKEvent) {
        event.title = details.title
        event.location = details.location.isEmpty ? nil : details.location
        event.notes = details.notes.isEmpty ? nil : details.notes
        event.startDate = details.start
        event.endDate = details.end
        event.alarms = details.hasReminder ? [EKAlarm(relativeOffset: VisitCalendar.reminderOffset)] : nil
    }

    /// PlowR's calendars, the one it keeps the ID of first: that one, even
    /// renamed, and any "PlowR" calendar, such as one another of the user's
    /// devices made in iCloud. Only in iCloud or on this device.
    private func plowRCalendars() -> [EKCalendar] {
        let keptID = defaults.string(forKey: Self.calendarIDKey)
        let calendars = store.calendars(for: .event).filter { calendar in
            guard calendar.allowsContentModifications,
                  let source = calendar.source, Self.isOwnAccount(type: source.sourceType, title: source.title)
            else { return false }
            return calendar.calendarIdentifier == keptID || calendar.title == Self.calendarTitle
        }
        let kept = calendars.filter { $0.calendarIdentifier == keptID }
        let others = calendars.filter { $0.calendarIdentifier != keptID }
        if kept.isEmpty, let first = others.first {
            defaults.set(first.calendarIdentifier, forKey: Self.calendarIDKey)
        }
        return kept + others
    }

    /// A new "PlowR" calendar: in iCloud, where the user's calendars usually
    /// are, so it's on their other devices too; else on this iPhone.
    private func newCalendar() throws -> EKCalendar {
        let iCloud = store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
        let device = store.sources.first { $0.sourceType == .local }
        for source in [iCloud, device].compactMap({ $0 }) {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = Self.calendarTitle
            calendar.cgColor = PlowRColor.navyUIColor.cgColor
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
            } catch {
                store.reset()   // Nothing of the failed calendar is left to commit later.
                continue        // An account that doesn't allow new calendars: try the next.
            }
            defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
            return calendar
        }
        throw NoCalendarAccount()
    }
}

struct NoCalendarAccount: LocalizedError {
    var errorDescription: String? { "Neither iCloud nor this iPhone lets PlowR add a calendar." }
}
