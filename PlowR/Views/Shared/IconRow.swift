import SwiftUI

/// An icon beside its text, or above it at accessibility text sizes: a
/// fixed icon column leaves the text a sliver of the width there. Put the
/// row's trailing parts (a chevron, a close button) outside it, in the
/// `HStack` that holds it: they stay at the trailing edge.
struct IconRow<Icon: View, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat = PlowRLayout.space3
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PlowRLayout.space2))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout {
            icon
            content
        }
    }
}

/// Views in equal columns, left to right and top to bottom, each cell as
/// tall as the tallest in its row (the client page's 2 × 2 of actions at
/// accessibility text sizes).
struct EqualColumnsLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    private func cell(_ width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let cellWidth = cell(width)
        return stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let heights = rowHeights(subviews, width: width)
        return CGSize(width: width,
                      height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = rowHeights(subviews, width: bounds.width)
        let cellWidth = cell(bounds.width)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (cellWidth + spacing), y: y),
                                      proposal: ProposedViewSize(width: cellWidth, height: height))
            }
            y += height + spacing
        }
    }
}
