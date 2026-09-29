import WidgetKit
import AppIntents

/// Control Center's Complete Stop. This extension has no database to reach
/// the route with, so it opens PlowR's `plowr://completeStop` link, and the
/// app completes the stop you're at (CompleteStopAction). It used to only
/// open the app.
struct CompleteStopControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Current Stop"
    static var description = IntentDescription("Opens PlowR and marks the stop you're at as complete.")

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let link = URL(string: "plowr://completeStop") else { throw CocoaError(.fileReadInvalidFileName) }
        return .result(opensIntent: OpenURLIntent(link))
    }
}
