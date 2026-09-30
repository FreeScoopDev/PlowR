import SwiftUI

extension View {
    /// A screen's main action, full width: Apple's large prominent button in
    /// `tint`. The route flow's Start, Done, Complete and Review buttons were
    /// custom filled rectangles (greyed by hand when disabled) while End Route
    /// used this; now they all do. The label should fill the width
    /// (`.frame(maxWidth: .infinity)`).
    func primaryActionStyle(_ tint: Color) -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint)
    }

    /// The quieter choice beside a primary action (Skip, Not Now).
    func secondaryActionStyle() -> some View {
        buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.secondary)
    }
}
