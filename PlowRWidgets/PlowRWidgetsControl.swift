import AppIntents
import SwiftUI
import WidgetKit

/// Control Center's Complete Stop. It shows the client whose stop it
/// completes, and its intent carries that stop, drawn from the widget data
/// when Control Center draws the control; the app reloads the control
/// whenever that data changes.
struct PlowRWidgetsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetDataStore.controlKind, provider: ShownStopProvider()) { stop in
            ControlWidgetButton(action: CompleteStopControlIntent(stopID: stop.id)) {
                Label(stop.name.isEmpty ? "Complete Stop" : stop.name, systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("Complete Current Stop")
        .description("Opens PlowR and marks the stop you're at as complete.")
    }
}

/// The stop the control completes: the one the widget shows.
struct ShownStop {
    var id: UUID?
    var name: String
}

struct ShownStopProvider: ControlValueProvider {
    var previewValue: ShownStop { ShownStop(id: nil, name: "") }

    func currentValue() async throws -> ShownStop {
        let data = WidgetDataStore.read()
        guard let id = data?.shownStopID else { return ShownStop(id: nil, name: "") }
        return ShownStop(id: id, name: data?.nextStopName ?? "")
    }
}
