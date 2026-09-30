import SwiftUI

/// The coloured bar down the left of a list row (a client's, a document's, a
/// visit's), saying its status at a glance. One size everywhere: the
/// Schedule's used to be shorter than the others.
struct AccentBar: View {
    let color: Color

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 4, height: 48)
    }
}

/// A stop's number in a route's list of stops: blue, or green once it's done.
/// Route details, building or editing a route and the route screen's Up Next
/// used to draw it four ways (a solid circle with a shadow, a tinted circle,
/// a bare number at two widths). The route map's pins stay solid: they have
/// to stand out on a map.
struct StopNumberBadge: View {
    let number: Int
    var isDone = false

    var body: some View {
        let color: Color = isDone ? .green : .blue
        Text("\(number)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.15), in: Circle())
            .accessibilityLabel("Stop \(number)\(isDone ? ", done" : "")")
    }
}
