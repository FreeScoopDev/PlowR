import Foundation
import SwiftData

/// Deleting a visit from the Schedule. It's asked first, naming the client
/// and the day: one swipe used to delete it, with no way back. A visit in a
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

    /// Deletes `visit`, and with `.thisAndFuture` the series' visits after
    /// it. The series then ends the day before, so completing an earlier
    /// visit doesn't add the deleted ones back (ScheduledVisit.continuation).
    static func delete(_ visit: ScheduledVisit, scope: Scope, among visits: [ScheduledVisit],
                       in context: ModelContext, calendar: Calendar = .current) {
        if scope == .thisAndFuture {
            let later = following(visit, among: visits)
            let laterIDs = Set(later.map(\.id))
            if let end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: visit.scheduledDate)) {
                for other in visits where other.seriesID == visit.seriesID && other.operatorID == visit.operatorID
                    && other.id != visit.id && !laterIDs.contains(other.id) {
                    if other.recurrenceEndDate.map({ $0 > end }) ?? true { other.recurrenceEndDate = end }
                }
            }
            for other in later { context.delete(other) }
        }
        context.delete(visit)
    }
}
