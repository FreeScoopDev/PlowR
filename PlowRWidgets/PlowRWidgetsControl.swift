import AppIntents
import SwiftUI
import WidgetKit

struct PlowRWidgetsControl: ControlWidget {
    static let kind: String = "com.Scoops.PlowR.CompleteStop"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CompleteStopControlIntent()) {
                Label("Complete Stop", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("Complete Current Stop")
        .description("Mark the current route stop as complete from Control Center.")
    }
}
