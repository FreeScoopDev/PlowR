import Foundation
import Observation
import SwiftData
import SwiftUI

/// The one Undo offered off the route screen: after deleting a visit (or a
/// series' visits), Skip, and the Schedule's Complete. The toast
/// (`UndoToast`) shows it for `window` seconds, then it's gone.
///
/// One offer at a time. A new one ends the one before, committing anything
/// it was holding. Nothing is kept on disk: an offer dies with the process.
/// (The route screen keeps its own Undo, `ActiveRouteStore.undoLastCompletion`,
/// with its own 30 s window; only the bar's look is shared.)
///
/// **Deletes wait for the window.** An undoable delete doesn't delete: it
/// puts the models' IDs in `pendingDeletions`, the screens hide them
/// (`isPendingDeletion`), and the delete is done (and saved) when the window
/// ends, a new offer replaces this one, or the app goes to the background.
/// Undo just drops the IDs: nothing was changed, nothing synced. Deleting and
/// then inserting a copy back would give the copy a new ID (breaking the
/// calendar's `plowr://visit/<id>` link and anything holding the visit's ID,
/// a record's or an invoice's `visitID`), sync a delete and a create to every
/// device, and leave another device time to act on the delete. Known costs:
/// - If the app crashes inside the window the delete never happens and the
///   visit comes back. That's the safe failure: no data lost.
/// - Other devices and `CalendarSync` see the visit up to `window` longer.
/// - A model deleted meanwhile by sync is skipped at commit.
@MainActor
@Observable
final class UndoCenter {
    static let shared = UndoCenter()

    /// How long an offer lasts.
    static let window: TimeInterval = 10

    /// What `undo` did.
    enum Result: Equatable {
        case undone
        /// The window had passed. Nothing was changed (a pending delete was done).
        case expired
        /// What the action changed was changed again since (sync, another
        /// screen). Nothing was touched.
        case changed
        /// No offer, already undone, or a different offer than the one tapped.
        case nothingToUndo
    }

    /// What the toast shows.
    struct Offer: Identifiable, Equatable {
        let id: UUID
        var title: String
        var systemImage: String
        /// The Undo button's VoiceOver label, e.g. "Undo skipping Pat".
        var accessibilityLabel: String
        var expiresAt: Date
    }

    private(set) var offer: Offer?
    /// The models an undoable delete is holding back, by `persistentModelID`.
    private(set) var pendingDeletions: Set<PersistentIdentifier> = []

    @ObservationIgnored private var undoAction: (() -> Result)?
    /// Does the pending delete: run when the offer ends any way but Undo or `discardAll`.
    @ObservationIgnored private var commitAction: (() -> Void)?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private(set) var context: ModelContext?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let autoExpire: Bool
    @ObservationIgnored private let announce: (String) -> Void

    /// `autoExpire: false` (tests) leaves ending the window to `endIfExpired()`.
    init(now: @escaping () -> Date = Date.init, autoExpire: Bool = true,
         announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }) {
        self.now = now
        self.autoExpire = autoExpire
        self.announce = announce
    }

    /// The main context, given at launch (PlowRApp.init) as the route store's is.
    func configure(context: ModelContext) {
        self.context = context
    }

    /// Whether `model` is waiting to be deleted: screens leave it out.
    func isPendingDeletion(_ model: some PersistentModel) -> Bool {
        !pendingDeletions.isEmpty && pendingDeletions.contains(model.persistentModelID)
    }

    // MARK: - Offers

    /// Offers Undo for an action just done, ending (and committing) the one
    /// before. `undo` puts things back, or returns `.changed` having touched
    /// nothing. With `pending`, the models are held back from deleting until
    /// the offer ends, when `commit` deletes them.
    func offer(title: String, systemImage: String, accessibilityLabel: String,
               pending: Set<PersistentIdentifier> = [], commit: (() -> Void)? = nil,
               undo: @escaping () -> Result) {
        end()
        let offer = Offer(id: UUID(), title: title, systemImage: systemImage,
                          accessibilityLabel: accessibilityLabel,
                          expiresAt: now().addingTimeInterval(Self.window))
        self.offer = offer
        undoAction = undo
        commitAction = commit
        pendingDeletions = pending
        announce("\(title). Undo available.")
        guard autoExpire else { return }
        // The center's, not a view's: the delete is done even if no toast is on screen.
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.window))
            guard !Task.isCancelled, let self, self.offer?.id == offer.id else { return }
            self.end()
        }
    }

    /// Takes back the offer's action (`id`: the one the toast showed).
    /// Refused once its window has passed (a pending delete is then done) or
    /// when it was changed since. Either way the offer ends.
    @discardableResult
    func undo(_ id: UUID? = nil) -> Result {
        guard let offer, let action = undoAction, id == nil || id == offer.id else { return .nothingToUndo }
        guard now() <= offer.expiresAt else {
            end()
            return .expired
        }
        // Dropped first: a delete is undone by never doing it.
        clear()
        return action()
    }

    /// Ends the offer: a pending delete is done. The window ending, a new
    /// offer, and the app going to the background (PlowRApp) all end it.
    func end() {
        let commit = commitAction
        clear()
        commit?()
    }

    /// Ends the offer if its window has passed.
    func endIfExpired() {
        guard let offer, now() > offer.expiresAt else { return }
        end()
    }

    /// Drops the offer and any pending delete without doing it: Delete
    /// Account & Data, which deletes or forgets everything anyway.
    func discardAll() {
        clear()
    }

    private func clear() {
        expiry?.cancel()
        expiry = nil
        offer = nil
        undoAction = nil
        commitAction = nil
        if !pendingDeletions.isEmpty { pendingDeletions = [] }
    }
}
