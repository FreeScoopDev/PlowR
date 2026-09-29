import AppIntents
import Foundation

/// Control Center's Complete Stop. Compiled into the app and the widget
/// extension: the control is the extension's, and because the intent opens
/// PlowR, the system runs it in the app, where the route is. It completes
/// the stop the widget shows, if that's still the current one. What it does
/// there is `complete(shownStop:)`, which each target defines for itself.
///
/// It used to live in the extension only. It opened the app and nothing
/// more; then it returned an OpenURLIntent for the app to complete the stop
/// from a link, which on iOS 26 opened nothing at all (seen on a simulator:
/// "Failed to fetch metadata for OpenURLIntent").
struct CompleteStopControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Current Stop"
    static let description = IntentDescription("Opens PlowR and marks the stop you're at as complete.")
    static let openAppWhenRun = true
    /// Control Center's only: Siri and Shortcuts have Complete Current Stop.
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        if let stopID = WidgetDataStore.read()?.shownStopID {
            Self.complete(shownStop: stopID)
        }
        return .result()
    }
}
