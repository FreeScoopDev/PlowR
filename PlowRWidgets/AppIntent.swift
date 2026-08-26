import WidgetKit
import AppIntents

struct CompleteStopControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Current Stop"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
