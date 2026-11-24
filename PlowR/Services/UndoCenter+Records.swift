import Foundation
import SwiftData

/// Undo for Mark Paid, deleting a client photo and Optimize Order: each
/// ends the offer before (committing a pending delete) first, does what it
/// did before Undo existed, and offers to take it back.
extension UndoCenter {
    /// Mark Paid (`Payments.payInFull`, unchanged). Undo takes back only the
    /// payment this made (`MarkedPaid.undo`). After the window the payment
    /// can still be removed on the invoice's Payments screen.
    func markPaid(_ invoice: Proposal, now: Date = .now) {
        end()
        guard let context, !invoice.isGone,
              let marked = Payments.payInFull(invoice, in: context, now: now) else { return }
        // Saved, so the payment has the permanent ID `isGone` looks for.
        try? context.save()
        offer(title: marked.title, systemImage: PlowRSymbol.payment.name,
              accessibilityLabel: marked.accessibilityLabel,
              undo: { [weak self] in
                  guard let context = self?.context else { return .nothingToUndo }
                  return marked.undo(in: context)
              })
    }

    /// Deleting a client photo, held back for the window (see UndoCenter):
    /// the gallery hides it, and it's deleted when the offer ends. Undo drops
    /// it from the pending set; nothing changed. Never deleted and inserted
    /// again: its image is kept outside the database and would be uploaded
    /// to iCloud again, under a new ID.
    func delete(_ photo: StopPhoto) {
        end()
        guard let context, !photo.isGone else { return }
        // Saved first, so the ID held is the permanent one a fetch returns.
        if context.hasChanges { try? context.save() }
        offer(title: "Deleted photo", systemImage: PlowRSymbol.delete.name,
              accessibilityLabel: "Undo deleting photo",
              pending: [photo.persistentModelID],
              commit: { [weak self] in
                  guard let context = self?.context, !photo.isGone else { return }
                  context.delete(photo)
                  try? context.save()
              },
              undo: { .undone })
    }

    /// Optimize Order rewrote `route`'s stop order from `before`. Offered
    /// only if an order changed; undo puts `before` back unless the stops
    /// were moved, added or removed since (`StopOrderSnapshot.restore`).
    func optimized(_ route: PlowRoute, from before: StopOrderSnapshot) {
        let after = StopOrderSnapshot(route.sortedStops)
        guard after != before else { return }
        end()
        guard let context else { return }
        try? context.save()
        let name = route.name.isEmpty ? "route" : route.name
        offer(title: "Optimized \(name)", systemImage: PlowRSymbol.route.name,
              accessibilityLabel: "Undo optimizing \(name)",
              undo: { [weak self] in
                  guard !route.isGone, before.restore(on: route.sortedStops, ifStill: after) else { return .changed }
                  try? self?.context?.save()
                  return .undone
              })
    }
}
