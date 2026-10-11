import SwiftUI

extension View {
    /// A List or Form in the 1.7 design: the warm page colour (deep green in
    /// dark mode) behind it, instead of the system's grey and black. Its
    /// rows take `PlowRColor.surface` with `.listRowBackground` on each
    /// Section: a row background set on the list itself doesn't reach them.
    func plowRGrouped() -> some View {
        scrollContentBackground(.hidden)
            .background(PlowRColor.ground)
    }
}
