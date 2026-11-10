import SwiftUI

/// The mark beside something that needs PlowR Pro. One view, so every screen
/// draws it the same way; whether to show it is the caller's rule.
struct ProMark: View {
    var body: some View {
        StatusChip("Pro", status: .neutral)
    }
}
