import SwiftUI

/// The coloured bar down the left of a list row (a client's, a document's, a
/// visit's), saying its status at a glance, in the status's fill colour
/// (`PlowRColor.Status`), or the brand with nothing to flag. One size
/// everywhere: the Schedule's used to be shorter than the others.
struct AccentBar: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let status: PlowRColor.Status?

    /// At accessibility text sizes the row is taller than 48 pt (its text
    /// wraps, its trailing column stacks below): the bar runs the row's height.
    var body: some View {
        let bar = Capsule().fill(status?.fill ?? PlowRColor.brand)
        if typeSize.isAccessibilitySize {
            bar.frame(width: 4).frame(minHeight: 48, maxHeight: .infinity)
        } else {
            bar.frame(width: 4, height: 48)
        }
    }
}

/// A stop's number in a route's list of stops: the brand, or the done
/// colour once it's done (1.7 tokens).
/// Route details, building or editing a route and the route screen's Up Next
/// used to draw it four ways (a solid circle with a shadow, a tinted circle,
/// a bare number at two widths). The route map's pins stay solid: they have
/// to stand out on a map.
struct StopNumberBadge: View {
    let number: Int
    var isDone = false
    /// At accessibility text sizes the circle grows with the number (capped
    /// at 56 pt) so the digit stays inside it. False keeps it at 28 pt, where
    /// the digit shrinks to fit instead: rows already narrow (the route
    /// builders, with delete and reorder controls) can't spare the width.
    var growsWithText = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var scaledSize: CGFloat = 28

    var body: some View {
        let size = growsWithText && typeSize.isAccessibilitySize ? min(scaledSize, 56) : 28
        let color: Color = isDone ? PlowRColor.Status.done.text : PlowRColor.brand
        Text("\(number)")
            .font(PlowRFont.label)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(2)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
            .accessibilityLabel("Stop \(number)\(isDone ? ", done" : "")")
    }
}
