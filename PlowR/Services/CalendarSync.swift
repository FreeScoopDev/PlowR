import CoreData
import Foundation
import SwiftData

/// Settings > Add Visits to Calendar: keeps a "PlowR" calendar in step with
/// the schedule. Off until the user turns it on. Turning it on asks for full
/// calendar access, which it needs to find its events again.
///
/// It syncs after the store saves or iCloud changes it, when the app comes
/// to the front, and when someone signs in. That covers every way a visit
/// changes (the Schedule tab's swipes, the edit screen, a repeat, another
/// device) without any screen calling it. Earlier versions added an event
/// when a visit was made and never touched it again, so skipped, moved and
/// deleted visits kept their events and reminders.
@MainActor
@Observable
final class CalendarSync {
    static let shared = CalendarSync(store: EventKitVisitCalendarStore())
    static let enabledKey = "calendarSyncEnabled"
    static let seenKey = "calendarSyncSeenVisits"

    /// The switch, kept in preferences.
    private(set) var isEnabled: Bool
    /// Asking for access: the switch shows on until the answer.
    private(set) var isAsking = false
    /// Settings says PlowR needs full calendar access and links to the
    /// Settings app, where only the user can give it.
    private(set) var needsAccess = false
    /// Why the last sync failed, until one works.
    private(set) var problem: String?
    /// The signed-in business. Nothing syncs while it's empty: signed out,
    /// or still being checked at launch, when a sync would remove every event.
    @ObservationIgnored var operatorID = "" {
        didSet { if operatorID != oldValue { scheduleSync() } }
    }

    @ObservationIgnored private let store: any VisitCalendarStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var toldCalendarIsOutOfReach = false
    /// Turned off without calendar access: PlowR's events are still there,
    /// to remove when access comes back.
    @ObservationIgnored private var removalOwed = false

    init(store: any VisitCalendarStore, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init, delay: Duration = .seconds(2)) {
        self.store = store
        self.defaults = defaults
        self.now = now
        self.delay = delay
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    func configure(context: ModelContext) {
        self.context = context
        for name in [ModelContext.didSave, Notification.Name.NSPersistentStoreRemoteChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSync() }
            }
        }
    }

    func setEnabled(_ on: Bool) async {
        guard on else { return turnOff() }
        removalOwed = false
        if store.access != .full {
            isAsking = true
            let granted = store.access == .canAsk ? await store.requestFullAccess() : false
            isAsking = false
            guard granted else {
                needsAccess = true
                return
            }
        }
        needsAccess = false
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        syncNow()
    }

    /// When the app comes to the front: access may have been changed in
    /// Settings, and the window has moved on.
    func refresh() {
        if store.access == .full {
            needsAccess = false
            if removalOwed, !isEnabled { removeForTurnOff() }
        } else if isEnabled {
            needsAccess = true
        }
        scheduleSync()
    }

    /// Syncs once things settle: a swipe, an edit or an iCloud import saves
    /// several times in a row.
    func scheduleSync() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// Brings the calendar in step with the schedule now, including changes
    /// not saved yet. Does nothing unless it's turned on, with full access,
    /// and someone is signed in.
    func syncNow() {
        pending?.cancel()
        guard isEnabled, store.access == .full, !operatorID.isEmpty, let context else { return }
        let window = VisitCalendar.window(from: now())
        do {
            guard let events = try store.events(in: window, create: true) else { return }
            let visits = try Self.visits(in: window, orFor: events, from: context)
            let seenBefore = seen
            let changes = VisitCalendar.changes(visits: visits, operatorID: operatorID, events: events,
                                                seen: seenBefore, window: window)
            if !changes.isEmpty { try store.apply(changes) }
            let seenNow = VisitCalendar.seen(visits: visits, events: events, before: seenBefore, window: window)
            if seenNow != seenBefore { seen = seenNow }
            problem = nil
        } catch {
            problem = "Couldn't update the “PlowR” calendar. \(error.localizedDescription)"
        }
    }

    /// Delete Account & Data: turns sync off and removes every event PlowR
    /// added, and its calendar.
    ///
    /// Without calendar access (turned off in the Settings app) PlowR can't
    /// see the calendar to remove it: that fails, once, saying so, so the user
    /// can allow access or delete the calendar in Calendar. Asked again, it
    /// goes ahead: PlowR can't tell whether they have.
    func eraseAll() throws {
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        if store.access != .full, store.remembersCalendar, !toldCalendarIsOutOfReach {
            toldCalendarIsOutOfReach = true
            throw CalendarOutOfReach()
        }
        try removeEverything()
    }

    private func turnOff() {
        isEnabled = false
        defaults.set(false, forKey: Self.enabledKey)
        needsAccess = false
        removeForTurnOff()
    }

    /// Tried again when the app comes back with access, if it couldn't be done.
    private func removeForTurnOff() {
        if store.access != .full, store.remembersCalendar {
            problem = CalendarOutOfReach().localizedDescription
            removalOwed = true
            return
        }
        do {
            try removeEverything()
            problem = nil
            removalOwed = false
        } catch {
            problem = "Couldn't remove the “PlowR” calendar's events. \(error.localizedDescription)"
            removalOwed = true
        }
    }

    /// Every event PlowR added, in any year, then its calendars, unless the
    /// user put events of their own in them.
    private func removeEverything() throws {
        pending?.cancel()
        seen = []
        guard store.access == .full else { return }
        var plowRs: [String] = []
        var found: Set<String> = []     // An event across two spans is found twice.
        for span in VisitCalendar.allTime {
            guard let events = try store.events(in: span, create: false) else { return }
            for event in events where event.visitID != nil && found.insert(event.id).inserted {
                plowRs.append(event.id)
            }
        }
        if !plowRs.isEmpty { try store.apply(plowRs.map { .remove(eventID: $0) }) }
        try store.removeEmptyCalendars(searching: VisitCalendar.allTime)
    }

    /// Visits this device had with a date in the window at the last sync.
    private var seen: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Self.seenKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { defaults.set(newValue.map(\.uuidString).sorted(), forKey: Self.seenKey) }
    }

    /// The visits dated in `window`, and any other visit one of `events` is
    /// for, wherever it's been moved to.
    private static func visits(in window: DateInterval, orFor events: [CalendarEvent],
                               from context: ModelContext) throws -> [ScheduledVisit] {
        let start = window.start, end = window.end
        var visits = try context.fetch(FetchDescriptor<ScheduledVisit>(
            predicate: #Predicate { $0.scheduledDate >= start && $0.scheduledDate < end }))
        let others = Array(Set(events.compactMap(\.visitID)).subtracting(visits.map(\.id)))
        if !others.isEmpty {
            visits += try context.fetch(FetchDescriptor<ScheduledVisit>(
                predicate: #Predicate { others.contains($0.id) }))
        }
        return visits
    }
}

struct CalendarOutOfReach: LocalizedError {
    var errorDescription: String? {
        "PlowR can't reach its “PlowR” calendar because its calendar access is turned off. Delete that calendar in the Calendar app, or allow PlowR full access in the Settings app and try again."
    }
}
