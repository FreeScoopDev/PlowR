import AppIntents
import ActivityKit

// MARK: - Intents

struct CompleteCurrentStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Current Stop"
    static var description = IntentDescription("Mark the stop you're at as complete in PlowR, and hear which stop is next.")

    // Hands-free, without opening the app (see CompleteStopAction). The stop
    // meant is the current one, unless iCloud has changed it unseen.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = ActiveRouteStore.shared
        let reply = CompleteStopAction.run(in: store, expecting: store.currentStopID)
        return .result(dialog: "\(reply.text)")
    }
}

struct NotifyNextClientIntent: AppIntent {
    static var title: LocalizedStringResource = "Notify Next Client"
    static var description = IntentDescription("Open PlowR to notify the next client on your route.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteSessionManager.shared.onNotifyNext?()
        return .result(dialog: "Opening notification prompt.")
    }
}

// MARK: - Shortcuts

// Shortcut phrases the user can say to Siri:
// "Complete current stop in PlowR"
// "Notify next client in PlowR"
struct PlowRShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteCurrentStopIntent(),
            phrases: [
                "Complete current stop in \(.applicationName)",
                "Done with this stop in \(.applicationName)"
            ],
            shortTitle: "Complete Stop",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: NotifyNextClientIntent(),
            phrases: [
                "Notify next client in \(.applicationName)",
                "Message next client in \(.applicationName)"
            ],
            shortTitle: "Notify Client",
            systemImageName: "message"
        )
    }
}
