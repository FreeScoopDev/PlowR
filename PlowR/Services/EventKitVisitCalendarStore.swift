import EventKit
import UIKit

/// The "PlowR" calendar, through EventKit. Only reads and changes that
/// calendar; `VisitCalendar` decides what goes in it.
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

    func requestFullAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(in window: DateInterval, create: Bool) throws -> [CalendarEvent]? {
        guard let calendar = try plowRCalendar(create: create) else { return nil }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
        return store.events(matching: predicate).map { event in
            let reminder = event.alarms?.contains { $0.relativeOffset == VisitCalendar.reminderOffset } ?? false
            let details = EventDetails(title: event.title ?? "", location: event.location ?? "",
                                       notes: event.notes ?? "", start: event.startDate, end: event.endDate,
                                       hasReminder: reminder)
            return CalendarEvent(id: event.calendarItemIdentifier, visitID: VisitCalendar.visitID(fromLink: event.url),
                                 details: details, created: event.creationDate)
        }
    }

    func apply(_ changes: [CalendarChange]) throws {
        guard let calendar = try plowRCalendar(create: true) else { return }
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

    func removeCalendarIfEmpty(in window: DateInterval) throws {
        guard let calendar = try plowRCalendar(create: false) else { return }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
        guard store.events(matching: predicate).isEmpty else { return }
        try store.removeCalendar(calendar, commit: true)
        defaults.removeObject(forKey: Self.calendarIDKey)
    }

    private static func write(_ details: EventDetails, to event: EKEvent) {
        event.title = details.title
        event.location = details.location.isEmpty ? nil : details.location
        event.notes = details.notes.isEmpty ? nil : details.notes
        event.startDate = details.start
        event.endDate = details.end
        event.alarms = details.hasReminder ? [EKAlarm(relativeOffset: VisitCalendar.reminderOffset)] : nil
    }

    /// PlowR's calendar: the one it made or found before, else a "PlowR"
    /// calendar another of the user's devices made (an iCloud calendar
    /// arrives here too), else a new one when `create` is true.
    private func plowRCalendar(create: Bool) throws -> EKCalendar? {
        if let id = defaults.string(forKey: Self.calendarIDKey),
           let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications {
            return calendar
        }
        let named = store.calendars(for: .event).first {
            $0.title == Self.calendarTitle && $0.allowsContentModifications
        }
        if let named {
            defaults.set(named.calendarIdentifier, forKey: Self.calendarIDKey)
            return named
        }
        guard create else { return nil }
        for source in sourcesForANewCalendar() {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = Self.calendarTitle
            calendar.cgColor = PlowRColor.navyUIColor.cgColor
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
            } catch {
                continue    // An account that doesn't allow new calendars: try the next.
            }
            defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
            return calendar
        }
        throw NoCalendarAccount()
    }

    /// iCloud, where the user's calendars usually are, so the PlowR calendar
    /// is on their other devices too; else this iPhone. Never another
    /// account (Google, Exchange), even as the default for new events: the
    /// privacy policy says client details stay on the device and in iCloud.
    private func sourcesForANewCalendar() -> [EKSource] {
        let iCloud = store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
        let device = store.sources.first { $0.sourceType == .local }
        return [iCloud, device].compactMap { $0 }
    }
}

struct NoCalendarAccount: LocalizedError {
    var errorDescription: String? { "Neither iCloud nor this iPhone lets PlowR add a calendar." }
}
