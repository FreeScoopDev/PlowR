import WidgetKit
import AppIntents

/// Control Center's Complete Stop. This extension has no database to reach
/// the route with, so it opens a PlowRLink naming the stop the widget shows,
/// and the app completes that stop if it's still the current one
/// (CompleteStopAction). It used to only open the app.
struct CompleteStopControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Current Stop"
    static var description = IntentDescription("Opens PlowR and marks the stop you're at as complete.")

    func perform() async throws -> some IntentResult & OpensIntent {
        let link = PlowRLink.completeStopControl(showing: WidgetDataStore.read())
        return .result(opensIntent: OpenURLIntent(try link.url.orThrow()))
    }
}

private struct NoLink: Error {}

private extension Optional where Wrapped == URL {
    func orThrow() throws -> URL {
        guard let url = self else { throw NoLink() }
        return url
    }
}
