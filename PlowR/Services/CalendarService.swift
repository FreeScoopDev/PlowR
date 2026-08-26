import EventKit
import UIKit

/// Syncs ScheduledVisit records to the user's Calendar.app via a dedicated "PlowR" calendar.
/// Uses write-only access on iOS 17+ and legacy access on iOS 16.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private var cachedCalendar: EKCalendar?
    private var accessGranted = false

    private init() {}

    func requestAccess() async -> Bool {
        if accessGranted { return true }
        let granted: Bool
        if #available(iOS 17, *) {
            granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
        }
        accessGranted = granted
        return granted
    }

    private func resolvedCalendar() -> EKCalendar? {
        if let cal = cachedCalendar { return cal }
        if let existing = store.calendars(for: .event).first(where: { $0.title == "PlowR" }) {
            cachedCalendar = existing
            return existing
        }
        guard let source = store.sources.first(where: { $0.sourceType == .local })
                         ?? store.sources.first else { return nil }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "PlowR"
        cal.source = source
        cal.cgColor = UIColor.systemBlue.cgColor
        try? store.saveCalendar(cal, commit: true)
        cachedCalendar = cal
        return cal
    }

    /// Adds a scheduled visit to Calendar and returns the EKEvent identifier for later removal.
    func addVisit(_ visit: ScheduledVisit) async -> String? {
        guard await requestAccess(), let cal = resolvedCalendar() else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = cal
        event.title = "PlowR: \(visit.clientName)"
        if !visit.clientAddress.isEmpty { event.location = visit.clientAddress }
        if !visit.notes.isEmpty { event.notes = visit.notes }
        event.startDate = visit.scheduledDate
        let duration = visit.estimatedMinutes > 0 ? Double(visit.estimatedMinutes) * 60 : 3600
        event.endDate = visit.scheduledDate.addingTimeInterval(duration)
        event.alarms = [EKAlarm(relativeOffset: -3600)] // 1-hour reminder
        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// Removes a previously synced Calendar event.
    func removeEvent(with identifier: String) async {
        guard await requestAccess(),
              let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
    }
}
