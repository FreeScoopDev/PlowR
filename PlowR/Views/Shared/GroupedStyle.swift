import SwiftUI

extension View {
    /// A List or Form in the 1.7 design: the page colour (warm in light mode,
    /// graphite in dark) behind it, instead of the system's grey and black. Its
    /// rows take `PlowRColor.surface` with `.listRowBackground` on each
    /// Section: a row background set on the list itself doesn't reach them.
    func plowRGrouped() -> some View {
        scrollContentBackground(.hidden)
            .background(PlowRColor.ground)
    }
}

/// A grouped section's title in `PlowRColor.inkSecondary`. iOS draws these
/// titles in its own pale grey (about 3.4:1 on white). A `.foregroundStyle` on
/// the List was tried instead and rejected: it also turned tinted row buttons
/// from the brand colour to ink. So each title is styled where it is written;
/// the system header font and text case are kept.
struct SectionTitle: View {
    private let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }

    /// For titles that are data (a group label, a month), not a localizable key.
    init<S: StringProtocol>(verbatim title: S) { text = Text(verbatim: String(title)) }

    var body: some View {
        text.foregroundStyle(PlowRColor.inkSecondary)
    }
}

extension Section where Parent == SectionTitle, Footer == EmptyView, Content: View {
    /// A Section whose title is drawn by `SectionTitle`. Use this instead of
    /// `Section("…")` in a List or Form (scripts/check_list_rows.py checks).
    /// The label is `title:` so it can't be mistaken for SwiftUI's own.
    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SectionTitle(title) })
    }

    /// For a title that is a String variable rather than a literal.
    init<S: StringProtocol>(title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SectionTitle(verbatim: title) })
    }
}
