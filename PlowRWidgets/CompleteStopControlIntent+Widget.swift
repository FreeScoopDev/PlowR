import Foundation

extension CompleteStopControlIntent {
    /// The extension has no route to complete a stop on. The intent opens
    /// PlowR, so the system runs it there instead; were it ever run here,
    /// PlowR would only open.
    @MainActor
    static func complete(shownStop stopID: UUID) {}
}
