import SwiftUI

/// A snow contract's trigger: work starts at this depth of snow. Its own
/// file, as snow-only features are, and shown only when the contract covers
/// a snow service. The Dashboard's storm card goes by it (StormWatch).
struct ContractTriggerSection: View {
    @Binding var inches: Double

    var body: some View {
        Section {
            Stepper(value: $inches, in: 0...12, step: 0.5) {
                LabeledContent("Snow Trigger", value: inches > 0 ? "\(inches.formatted()) in or more" : "Every snowfall")
            }
        } footer: {
            Text("Snow clearing starts at this depth. The Dashboard shows a storm card when the forecast reaches it.")
        }
    }
}

/// The trigger on a contract's page.
struct ContractTriggerRow: View {
    let inches: Double

    var body: some View {
        LabeledContent("Snow Trigger", value: "\(inches.formatted()) in or more")
    }
}
