import Foundation

extension CompleteStopControlIntent {
    /// In PlowR, where the system runs the intent: completes the stop the
    /// widget showed if it's still the current one. The route screen, up
    /// while a route is in progress, shows the next stop or why not.
    @MainActor
    static func complete(shownStop stopID: UUID) {
        RouteSessionManager.shared.completeStopMessage = CompleteStopAction.controlCenter(
            stopID: stopID, in: .shared, role: UserDefaults.standard.string(forKey: UserRole.key))
    }
}
