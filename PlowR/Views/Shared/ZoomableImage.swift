import SwiftUI
import UIKit

/// A photo shown full width that pinches to zoom (up to 5×) and zooms 2× on
/// a double tap: a client's photo, an expense's receipt.
struct ZoomableImage: View {
    let image: UIImage
    /// What VoiceOver reads for the photo, such as "Receipt photo".
    let label: String

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .accessibilityLabel(label)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1.0, min(lastScale * value, 5.0))
                    }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1.05 {
                        scale = 1.0
                        lastScale = 1.0
                    } else {
                        scale = 2.0
                        lastScale = 2.0
                    }
                }
            }
    }
}
