import AppIntents
import Foundation

/// Control Center's Complete Stop. Compiled into the app and the widget
/// extension: the control is the extension's, and because the intent opens
/// PlowR, the system runs it in the app, where the route is. What it does
/// there is `complete(shownStop:)`, which each target defines for itself.
///
/// It completes `stopID`, the stop the control showed when it was tapped
/// (the control draws it from the widget data), and only if that's still
/// the current stop. Read in the app instead, it would be whatever the app
/// had just moved the route to on launch, a stop the user may never have
/// seen, and a second tap would complete the next stop.
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

    /// The stop the control showed, as a UUID string. None with no route in
    /// progress or every stop done: then it only opens PlowR.
    @Parameter(title: "Stop")
    var stopID: String?

    init() {}

    init(stopID: UUID?) {
        self.stopID = stopID?.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let stopID, let shown = UUID(uuidString: stopID) {
            Self.complete(shownStop: shown)
        }
        return .result()
    }
}
