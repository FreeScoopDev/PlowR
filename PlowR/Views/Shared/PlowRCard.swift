import SwiftUI

/// A card on the page's ground: the surface colour with a hairline border,
/// no shadow (1.7). The Dashboard's cards, the storm card and the route
/// screen's stop card are drawn this way. It was `DashCard`, on the system's
/// grouped grey.
struct PlowRCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous)
        VStack(spacing: 0) { content }
            .background(PlowRColor.surface, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(PlowRColor.line))
    }
}
