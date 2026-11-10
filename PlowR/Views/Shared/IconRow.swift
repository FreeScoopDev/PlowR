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

/// `IconRow` with a trailing control (a close button). At accessibility
/// sizes the control sits on the icon's line, so the text has the full width.
struct IconCardRow<Icon: View, Content: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat = PlowRLayout.space3
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                HStack(alignment: .top) {
                    icon
                    Spacer(minLength: 0)
                    trailing
                }
                content
            }
        } else {
            HStack(alignment: .top, spacing: spacing) {
                icon
                content
                Spacer(minLength: 0)
                trailing
            }
        }
    }
}

extension DynamicTypeSize {
    /// Where a row's trailing column (an amount, a status, a count) lines
    /// up: the trailing edge beside the text, the leading edge once
    /// `AdaptiveRow` stacks it under the text.
    var trailingColumnAlignment: HorizontalAlignment {
        isAccessibilitySize ? .leading : .trailing
    }

    /// The "· " that joins details on one line; stacked details have no
    /// line to join, so it goes.
    var detailSeparator: String {
        isAccessibilitySize ? "" : "· "
    }
}

private struct WholeValue: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .lineLimit(typeSize.isAccessibilitySize ? 1 : nil)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 0.6 : 1)
    }
}

extension View {
    /// A phone number or amount: at accessibility sizes it stays on one
    /// line and scales down a little rather than break mid-value.
    func wholeValue() -> some View { modifier(WholeValue()) }
}

/// A list row of a leading mark (an accent bar, a number), the main text
/// and a trailing column (amount, status, count), or at accessibility text
/// sizes the main text with the trailing column under it, full width and
/// leading-aligned: a trailing column leaves the text a sliver otherwise.
/// Put an accessory that stays at the trailing edge (a chevron, a pencil)
/// outside it, in the `HStack` that holds it. Below accessibility sizes it
/// is the plain `HStack` the rows had: mark, text, `Spacer`, trailing.
struct AdaptiveRow<Leading: View, Main: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat? = 12
    var spacerMinLength: CGFloat?
    @ViewBuilder let leading: Leading
    @ViewBuilder let main: Main
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if typeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: spacing) {
                leading
                VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                    main
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: alignment, spacing: spacing) {
                leading
                main
                Spacer(minLength: spacerMinLength)
                trailing
            }
        }
    }
}

extension AdaptiveRow where Leading == EmptyView {
    init(alignment: VerticalAlignment = .center, spacing: CGFloat? = 12, spacerMinLength: CGFloat? = nil,
         @ViewBuilder main: () -> Main, @ViewBuilder trailing: () -> Trailing) {
        self.init(alignment: alignment, spacing: spacing, spacerMinLength: spacerMinLength,
                  leading: { EmptyView() }, main: main, trailing: trailing)
    }
}

/// A short run of details (a date and an average, two badges) that stacks
/// at accessibility text sizes instead of squeezing each into a sliver.
struct AdaptiveDetails<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat = 4
    @ViewBuilder let content: Content

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

/// A single-line text field that, at accessibility text sizes, grows to up
/// to four lines instead of hiding its value behind "…". Below them it is
/// the plain `TextField`. The value stays one line: Return ends editing as
/// it does in a plain field, and line breaks pasted or autofilled (an
/// address) become ", " rather than being dropped.
struct GrowingTextField: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Bool
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    /// `value` with each run of line breaks (and the spaces around it)
    /// turned into ", "; breaks at either end are dropped.
    static func singleLine(_ value: String) -> String {
        guard value.contains(where: \.isNewline) else { return value }
        let lines = value.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: ", ")
    }

    /// Return was pressed: `new` is `old` with one line break typed into
    /// it, wherever the cursor was. Anything bigger (a paste, AutoFill) isn't.
    static func isReturn(old: String, new: String) -> Bool {
        guard new.count == old.count + 1 else { return false }
        guard let at = zip(old.indices, new.indices).first(where: { old[$0.0] != new[$0.1] })?.1
            ?? new.indices.last else { return false }
        guard new[at].isNewline else { return false }
        var without = new
        without.remove(at: at)
        return without == old
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .onChange(of: text) { previous, value in
                    guard value.contains(where: \.isNewline) else { return }
                    // Return ends editing and changes nothing, as it does in a
                    // one-line field; a pasted break becomes ", ".
                    if Self.isReturn(old: previous, new: value) {
                        text = previous
                        focused = false
                    } else {
                        text = Self.singleLine(value)
                    }
                }
        } else {
            TextField(title, text: $text)
        }
    }
}
