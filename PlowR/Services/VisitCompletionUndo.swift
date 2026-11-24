import Foundation
import SwiftData

/// A day's visit before a completion completed it: what Undo puts back.
/// Shared by the route screen's Undo (ActiveRouteStore) and the Schedule's.
struct UndoVisitState {
    var visit: ScheduledVisit
    var status: VisitStatus
    var completedAt: Date?
    var serviceLogged: Bool

    init(visit: ScheduledVisit, status: VisitStatus, completedAt: Date?, serviceLogged: Bool) {
        self.visit = visit
        self.status = status
        self.completedAt = completedAt
        self.serviceLogged = serviceLogged
    }

    /// `visit` as it is now.
    init(of visit: ScheduledVisit) {
        self.init(visit: visit, status: visit.status, completedAt: visit.completedAt,
                  serviceLogged: visit.serviceLogged)
    }

    /// Puts the three fields back on the visit, writing only those that differ.
    func restore() {
        if visit.status != status { visit.status = status }
        if visit.completedAt != completedAt { visit.completedAt = completedAt }
        if visit.serviceLogged != serviceLogged { visit.serviceLogged = serviceLogged }
    }
}

/// The Schedule's Complete (swipe, and Past Due's button), with what it
/// changed kept so Undo can take it back: `ServiceLog.complete` itself is
/// unchanged; this reads around it, as `ActiveRouteStore.recordVisit` does
/// for Complete Stop.
///
/// Undo is refused (`.changed`, nothing touched) once the visit's status or
/// completion time, or its record's fields or photos, differ from how
/// completing left them: sync or another screen wrote to them since.
struct VisitCompletionUndo {
    /// The visit before.
    var before: UndoVisitState
    /// Its status and completion time as completing left them.
    var statusAfter: VisitStatus
    var completedAtAfter: Date?
    /// The `visit:<id>` record completing wrote to (nil: no client on file).
    var record: ServiceRecord?
    /// Its fields before, when it existed already: put back. nil when
    /// completing made it: deleted.
    var recordBefore: ServiceRecord.Fields?
    var recordAfter: ServiceRecord.Fields?
    var photosAfter: Set<UUID> = []
    /// Visits the series gained (ClientVisits.addNext), with their date then.
    var addedVisits: [(visit: ScheduledVisit, scheduledDate: Date)] = []

    /// Completes `visit` (`ServiceLog.complete`) and returns what Undo needs.
    static func complete(_ visit: ScheduledVisit, among visits: [ScheduledVisit], in context: ModelContext,
                         now: Date = .now) -> VisitCompletionUndo {
        let before = UndoVisitState(of: visit)
        let recordBefore = ServiceLog.record(forKey: ServiceLog.visitKey(visit.id), in: context)
            .map { ServiceRecord.Fields(of: $0) }
        let inSeries = visit.isRecurring && !visit.seriesID.isEmpty
        let seriesBefore = inSeries ? Set(ServiceLog.series(of: visit, in: context).map(\.id)) : []

        let record = ServiceLog.complete(visit, among: visits, in: context, now: now)

        var undo = VisitCompletionUndo(before: before, statusAfter: visit.status, completedAtAfter: visit.completedAt,
                                       record: record, recordBefore: recordBefore)
        if let record {
            undo.recordAfter = ServiceRecord.Fields(of: record)
            undo.photosAfter = Set(ServiceLog.photos(of: record, in: context).map(\.id))
        }
        if inSeries {
            undo.addedVisits = ServiceLog.series(of: visit, in: context)
                .filter { !seriesBefore.contains($0.id) }
                .map { ($0, $0.scheduledDate) }
        }
        return undo
    }

    /// Whether anything completing left was changed since.
    func isChanged(in context: ModelContext) -> Bool {
        let visit = before.visit
        if visit.isDeleted || visit.status != statusAfter || visit.completedAt != completedAtAfter { return true }
        guard let record, let recordAfter else { return false }
        if record.isDeleted || ServiceRecord.Fields(of: record) != recordAfter { return true }
        return !Set(ServiceLog.photos(of: record, in: context).map(\.id)).isSubset(of: photosAfter)
    }

    /// Takes the completion back, or refuses having touched nothing. Saves.
    func undo(in context: ModelContext) -> UndoCenter.Result {
        guard !isChanged(in: context) else { return .changed }
        let visit = before.visit
        if let record {
            if let recordBefore {
                recordBefore.restore(to: record)
            } else {
                // Made by completing. Billed only on the invoice already made
                // for its visit (billFromVisit), which stays: it's the visit's.
                let ownInvoice = record.invoiceID.isEmpty
                    || ServiceLog.invoice(ofVisit: visit, in: context)?.id.uuidString == record.invoiceID
                ServiceLog.deleteRecord(record, in: context, evenIfInvoiced: ownInvoice)
            }
        }
        before.restore()
        // The series' next visit, unless it's been worked on since.
        for added in addedVisits where !added.visit.isDeleted && added.visit.status == .scheduled
            && added.visit.scheduledDate == added.scheduledDate && added.visit.proposalID.isEmpty {
            context.delete(added.visit)
        }
        try? context.save()
        return .undone
    }
}
