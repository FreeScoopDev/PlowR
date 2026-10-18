import SwiftUI

/// Settings → Help → Help Guide: every topic of the guide, by section. The
/// copy is the bundled `HelpGuide.json`, the same file the website's page
/// is made from, so it needs no network.
struct HelpGuideView: View {
    var guide: HelpGuide = .shared

    var body: some View {
        List {
            Section {
                Text(HelpText.attributed(guide.lede))
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
            .listRowBackground(PlowRColor.surface)

            ForEach(guide.sections) { section in
                Section {
                    ForEach(section.topics) { topic in
                        NavigationLink {
                            HelpTopicView(topic: topic, guide: guide)
                        } label: {
                            HelpTopicRow(topic: topic)
                        }
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    if let outro = section.outro {
                        Text(HelpText.attributed(outro))
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }
            .listRowBackground(PlowRColor.surface)

            Section {
                Link(destination: guide.web) {
                    Label("Help on the Web", systemImage: "safari")
                }
            } footer: {
                Text("The same guide on getplowr.app, with screenshots.")
            }
            .listRowBackground(PlowRColor.surface)
        }
        .plowRGrouped()
        .navigationTitle("Help Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A topic in a list: its title, a Pro chip when it needs Pro, and its summary.
struct HelpTopicRow: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space1) {
            HStack(spacing: PlowRLayout.space2) {
                Text(topic.title)
                    .font(.body.weight(.semibold))
                if topic.pro {
                    StatusChip("Pro", status: .neutral)
                }
            }
            Text(HelpText.attributed(topic.summary))
                .font(.subheadline)
                .foregroundStyle(PlowRColor.inkSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

/// One topic: its steps, note and bullets, and a link to it on the website.
struct HelpTopicView: View {
    let topic: HelpTopic
    var guide: HelpGuide = .shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                    if topic.pro {
                        StatusChip("Pro", status: .neutral)
                    }
                    Text(HelpText.attributed(topic.lead ?? topic.summary))
                }
                .padding(.vertical, PlowRLayout.space1)
            }
            .listRowBackground(PlowRColor.surface)

            if !topic.steps.isEmpty {
                Section("Steps") {
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: PlowRLayout.space3) {
                            Text("\(index + 1)")
                                .font(PlowRFont.number)
                                .foregroundStyle(PlowRColor.brand)
                                .frame(minWidth: 22, alignment: .trailing)
                                .accessibilityHidden(true)
                            Text(HelpText.attributed(step))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("Step \(index + 1): ") + Text(HelpText.attributed(step)))
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }

            if !topic.bullets.isEmpty {
                Section {
                    ForEach(topic.bullets, id: \.self) { bullet in
                        Text(HelpText.attributed(bullet))
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }

            if let note = topic.note {
                Section {
                    Text(HelpText.attributed(note))
                        .font(.subheadline)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
                .listRowBackground(PlowRColor.surface)
            }

            Section {
                Link(destination: guide.webURL(for: topic)) {
                    Label("View on the Web", systemImage: "safari")
                }
            }
            .listRowBackground(PlowRColor.surface)
        }
        .plowRGrouped()
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What a screen's Help item opens: that screen's topics, then the whole guide.
struct HelpTopicsSheet: View {
    let screen: HelpScreen
    var guide: HelpGuide = .shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(guide.topics(for: screen)) { topic in
                        NavigationLink {
                            HelpTopicView(topic: topic, guide: guide)
                        } label: {
                            HelpTopicRow(topic: topic)
                        }
                    }
                }
                .listRowBackground(PlowRColor.surface)

                Section {
                    NavigationLink {
                        HelpGuideView(guide: guide)
                    } label: {
                        Label("All Help Topics", systemImage: PlowRSymbol.help.name)
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }
            .plowRGrouped()
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A screen's Help button, for its toolbar: opens `HelpTopicsSheet`.
struct HelpToolbarButton: View {
    let screen: HelpScreen
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: PlowRSymbol.help.name)
        }
        .accessibilityLabel("Help")
        .sheet(isPresented: $showing) {
            HelpTopicsSheet(screen: screen)
        }
    }
}
