import Foundation
import SwiftData

/// Deleting a visit from the Schedule. It's asked first, naming the client
/// and the day, and Undo is offered for a few seconds after (UndoCenter). A visit in a
/// repeating series with visits still to come offers the same two choices
/// the visit editor gives for a change: this visit only, or this and all
/// future visits.
enum VisitDeletion {
    enum Scope: Equatable {
        case thisVisit
        case thisAndFuture
    }

    /// The confirmation's title.
    static func title(for visit: ScheduledVisit) -> String {
        let day = visit.scheduledDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let name = visit.clientName.isEmpty ? "this visit" : "\(visit.clientName)'s visit"
        return "Delete \(name) on \(day)?"
    }

    /// The visits after `visit` in its series still to do or skipped: what
    /// "This & All Future Visits" deletes besides it. A completed visit is a
    /// record and stays.
    static func following(_ visit: ScheduledVisit, among visits: [ScheduledVisit]) -> [ScheduledVisit] {
        guard visit.isRecurring, !visit.seriesID.isEmpty else { return [] }
        return visits.filter {
            $0.seriesID == visit.seriesID && $0.operatorID == visit.operatorID && $0.id != visit.id
                && $0.scheduledDate > visit.scheduledDate && $0.status != .completed
        }
    }

    /// Whether to offer "This & All Future Visits": only when there are any.
    static func offersSeries(_ visit: ScheduledVisit, among visits: [ScheduledVisit]) -> Bool {
        !following(visit, among: visits).isEmpty
    }

    /// The scope of the single "Delete Visit" (no series choice offered).
    /// Deleting the latest visit of a repeating series ends the series
    /// there, as "This & All Future Visits" would: otherwise completing the
    /// visit before it adds the deleted one back (ScheduledVisit.continuation).
    static func singleDeleteScope(for visit: ScheduledVisit, among visits: [ScheduledVisit]) -> Scope {
        guard visit.isRecurring, !visit.seriesID.isEmpty,
              !visits.contains(where: {
                  $0.seriesID == visit.seriesID && $0.operatorID == visit.operatorID && $0.id != visit.id
                      && $0.scheduledDate > visit.scheduledDate
              }) else { return .thisVisit }
        return .thisAndFuture
    }

    /// What a delete does, worked out when it's asked for: the visits to
    /// delete and, with `.thisAndFuture`, the series' other visits to end
    /// the day before. Nothing is changed until `commit`, so Undo (UndoCenter)
    /// just drops the plan.
    struct Plan {
        /// `visit` first, then the series' visits after it.
        var visits: [ScheduledVisit]
        /// The series' remaining visits, ended on `seriesEnd`.
        var ending: [ScheduledVisit] = []
        var seriesEnd: Date?
    }

    static func plan(_ visit: ScheduledVisit, scope: Scope, among visits: [ScheduledVisit],
                     calendar: Calendar = .current) -> Plan {
        guard scope == .thisAndFuture else { return Plan(visits: [visit]) }
        let later = following(visit, among: visits)
        let laterIDs = Set(later.map(\.id))
        guard let end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: visit.scheduledDate))
        else { return Plan(visits: [visit] + later) }
        let ending = visits.filter {
            $0.seriesID == visit.seriesID && $0.operatorID == visit.operatorID
                && $0.id != visit.id && !laterIDs.contains($0.id)
        }
        return Plan(visits: [visit] + later, ending: ending, seriesEnd: end)
    }

    /// Does `plan`: ends the series, then deletes its visits. One deleted
    /// meanwhile (another device) is skipped. Doesn't save.
    static func commit(_ plan: Plan, in context: ModelContext) {
        if let end = plan.seriesEnd {
            for other in plan.ending where !other.isGone {
                if other.recurrenceEndDate.map({ $0 > end }) ?? true { other.recurrenceEndDate = end }
            }
        }
        for visit in plan.visits where !visit.isGone { context.delete(visit) }
    }

    /// Deletes `visit`, and with `.thisAndFuture` the series' visits after
    /// it. The series then ends the day before, so completing an earlier
    /// visit doesn't add the deleted ones back (ScheduledVisit.continuation).
    /// At once, with no Undo: the Schedule goes through
    /// `UndoCenter.delete(_:scope:among:)`, which commits a plan later.
    static func delete(_ visit: ScheduledVisit, scope: Scope, among visits: [ScheduledVisit],
                       in context: ModelContext, calendar: Calendar = .current) {
        commit(plan(visit, scope: scope, among: visits, calendar: calendar), in: context)
    }
}
