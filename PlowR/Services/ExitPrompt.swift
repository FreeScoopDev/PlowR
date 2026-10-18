import Foundation

/// Whether leaving the current stop's job-site area offers the route
/// screen's "text the next client" prompt. Leaving never completes a stop:
/// GPS can wobble at the area's edge, a lot can be bigger than the area, and
/// a crew walks to the truck mid-job (Joe, 2026-10-18). It only offers the
/// text, once the phone has stayed out a while.
enum ExitPrompt {
    /// How long the phone must stay out of the area before the text is offered.
    static let delay: TimeInterval = 45
    /// An exit older than this isn't offered: the screen wasn't up, or the
    /// app was suspended, and the crew has moved on.
    static let maxAge: TimeInterval = 10 * 60

    /// `exitedAt`: the exit's time, as `ActiveRouteStore.siteExited` recorded
    /// it. `site`: the current stop's times now; its `leftAt` is that exit's
    /// time unless the phone came back in (or went out again) since.
    /// `canText`: the next client can be offered a text (they haven't asked
    /// not to be, and this device can text).
    static func shouldOffer(exitStopID: String, exitedAt: Date, currentStopID: UUID?, site: SiteTimes,
                            hasNextStop: Bool, canText: Bool, isPresentingSomething: Bool, now: Date) -> Bool {
        guard canText, hasNextStop, !isPresentingSomething,
              currentStopID?.uuidString == exitStopID,
              site.leftAt == exitedAt else { return false }
        let out = now.timeIntervalSince(exitedAt)
        return out >= delay && out <= maxAge
    }
}
