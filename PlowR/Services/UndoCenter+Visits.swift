import Foundation
import SwiftData

/// The Schedule's undoable actions: each ends the offer before (committing a
/// pending delete) first, does what it did before Undo existed, and offers
/// to take it back.
extension UndoCenter {
    /// Delete, held back for the window (see UndoCenter): the visit, or the
    /// series' visits the choice selects, are hidden, and deleted when the
    /// offer ends. Undo drops them from the pending set; nothing changed.
    func delete(_ visit: ScheduledVisit, scope: VisitDeletion.Scope, among visits: [ScheduledVisit]) {
        end()
        guard let context, !visit.isDeleted else { return }
        // Saved first, so the IDs held are the permanent ones a fetch returns
        // (a model not yet saved has a temporary ID that changes on save).
        if context.hasChanges { try? context.save() }
        let plan = VisitDeletion.plan(visit, scope: scope, among: visits.filter { !$0.isDeleted })
        let count = plan.visits.count
        let name = visit.clientName.isEmpty ? "a" : "\(visit.clientName)'s"
        let title = count == 1 ? "Deleted \(name) visit" : "Deleted \(count) visits"
        offer(title: title, systemImage: PlowRSymbol.delete.name,
              accessibilityLabel: count == 1 ? "Undo deleting \(name) visit" : "Undo deleting \(count) visits",
              pending: Set(plan.visits.map(\.persistentModelID)),
              commit: { [weak self] in
                  guard let context = self?.context else { return }
                  VisitDeletion.commit(plan, in: context)
                  try? context.save()
              },
              undo: { .undone })
    }

    /// Skip: the visit was scheduled. Undo puts that back while it's still skipped.
    func skip(_ visit: ScheduledVisit) {
        end()
        let before = visit.status
        visit.status = .skipped
        let name = Self.name(of: visit)
        offer(title: "Skipped \(name)", systemImage: PlowRSymbol.skip.name,
              accessibilityLabel: "Undo skipping \(name)",
              undo: { [weak self] in
                  guard !visit.isDeleted, visit.status == .skipped else { return .changed }
                  visit.status = before
                  try? self?.context?.save()
                  return .undone
              })
    }

    /// Complete (ServiceLog.complete through VisitCompletionUndo).
    func complete(_ visit: ScheduledVisit, among visits: [ScheduledVisit], now: Date = .now) {
        end()
        guard let context, !visit.isDeleted else { return }
        let completion = VisitCompletionUndo.complete(visit, among: visits.filter { !$0.isDeleted },
                                                      in: context, now: now)
        let name = Self.name(of: visit)
        offer(title: "Completed \(name)", systemImage: PlowRSymbol.complete.name,
              accessibilityLabel: "Undo completing \(name)",
              undo: { [weak self] in
                  guard let context = self?.context else { return .nothingToUndo }
                  return completion.undo(in: context)
              })
    }

    private static func name(of visit: ScheduledVisit) -> String {
        visit.clientName.isEmpty ? "visit" : visit.clientName
    }
}
