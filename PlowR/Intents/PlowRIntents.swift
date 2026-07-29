import AppIntents
import ActivityKit

// These intents appear in Siri and Shortcuts during an active route.
// They open the app to the active route screen for confirmation.

struct CompleteCurrentStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Current Stop"
    static var description = IntentDescription("Mark the current stop as complete in PlowR.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct NotifyNextClientIntent: AppIntent {
    static var title: LocalizedStringResource = "Notify Next Client"
    static var description = IntentDescription("Open PlowR to send a notification to the next client on your route.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

// Shortcut phrases the user can say to Siri:
// "Complete current stop in PlowR"
// "Skip this stop in PlowR"
// "Notify next client in PlowR"
struct PlowRShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteCurrentStopIntent(),
            phrases: ["Complete current stop in \(.applicationName)", "Done with this stop in \(.applicationName)"],
            shortTitle: "Complete Stop",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: NotifyNextClientIntent(),
            phrases: ["Notify next client in \(.applicationName)", "Message next client in \(.applicationName)"],
            shortTitle: "Notify Client",
            systemImageName: "message"
        )
    }
}
