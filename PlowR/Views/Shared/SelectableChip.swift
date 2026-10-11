import SwiftUI

extension View {
    /// A chip you pick (a preset, a weekday, a time): brand green with its
    /// own text colour when picked, the raised colour when not, so the pick
    /// shows by more than a tint. One look for every set of chips (1.7).
    func plowRChip(selected: Bool) -> some View {
        background(selected ? PlowRColor.brand : PlowRColor.raised)
            .foregroundStyle(selected ? PlowRColor.onBrand : PlowRColor.ink)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
