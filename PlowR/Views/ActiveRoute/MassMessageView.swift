import SwiftUI
import MessageUI

struct MassMessageView: View {
    let stops: [RouteStop]
    let allClients: [Client]

    @Environment(\.dismiss) private var dismiss

    @State private var includedIDs: Set<UUID>
    @State private var messageText = ""
    @State private var sendQueue: [RouteStop] = []
    @State private var groupPhones: [String] = []
    @State private var showingComposer = false
    @State private var sendStarted = false
    @State private var showingGroupWarning = false

    private let presets: [(String, String)] = [
        ("On My Way",     "I'll be at your property soon."),
        ("Move Vehicles", "Please move any vehicles from the driveway when you get a chance."),
        ("Running Late",  "Running slightly behind schedule — I'll be there shortly, thank you for your patience."),
        ("Weather Delay", "Weather is slowing things down a bit. I'm working safely and will be there soon."),
        ("All Clear",     "Everything will be cleared before you need to leave."),
    ]

    init(stops: [RouteStop], allClients: [Client]) {
        let messageable = stops.filter { !$0.isCustomStop && !$0.clientPhone.isEmpty }
        self.stops = messageable
        self.allClients = allClients
        let skipIDs = Set(allClients.filter { $0.skipNotificationPrompt }.map { $0.id })
        let included = Set(messageable
            .filter { !skipIDs.contains($0.clientID) }
            .map { $0.id })
        _includedIDs = State(initialValue: included)
    }

    private var selectedStops: [RouteStop] {
        stops.filter { includedIDs.contains($0.id) }
    }

    private var canSend: Bool {
        !selectedStops.isEmpty && !messageText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                presetsSection
                messageSection
                tagFilterSection
                recipientsSection
            }
            .navigationTitle("Message Clients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button { startSequentialSend() } label: {
                            Label("Send Individually (Recommended)", systemImage: "person.fill.checkmark")
                        }
                        Divider()
                        Button { showingGroupWarning = true } label: {
                            Label("Group Text (All recipients see each other)", systemImage: "person.2.fill")
                        }
                    } label: {
                        Text("Send (\(selectedStops.count))")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canSend || !MFMessageComposeViewController.canSendText())
                }
            }
        }
        .sheet(isPresented: $showingComposer, onDismiss: advanceSendQueue) {
            if !groupPhones.isEmpty {
                MessageComposer(recipients: groupPhones, body: messageText) { }
            } else if let stop = sendQueue.first {
                MessageComposer(recipients: [stop.clientPhone], body: messageText) { }
            }
        }
        .confirmationDialog(
            "Recipient Warning",
            isPresented: $showingGroupWarning,
            titleVisibility: .visible
        ) {
            Button("Send Group Text") { startGroupSend() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All recipients will see each other's phone numbers.")
        }
    }

    // MARK: - Sections

    private var presetsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { label, text in
                        let isActive = messageText.contains(text)
                        Button {
                            if isActive {
                                messageText = messageText
                                    .replacingOccurrences(of: " \(text)", with: "")
                                    .replacingOccurrences(of: text, with: "")
                                    .trimmingCharacters(in: .whitespaces)
                            } else {
                                messageText = messageText.isEmpty ? text : "\(messageText) \(text)"
                            }
                        } label: {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isActive ? Color.blue : Color(.systemGray5))
                                .foregroundStyle(isActive ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: {
            Text("Quick Presets").textCase(nil)
        }
    }

    private var messageSection: some View {
        Section {
            TextField("Write your message…", text: $messageText, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Message").textCase(nil)
        } footer: {
            Text("\(selectedStops.count) of \(stops.count) clients selected.")
        }
    }

    private var recipientsSection: some View {
        Section {
            ForEach(stops) { stop in
                Toggle(isOn: Binding(
                    get: { includedIDs.contains(stop.id) },
                    set: { on in
                        if on { includedIDs.insert(stop.id) }
                        else  { includedIDs.remove(stop.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.clientName).font(.subheadline)
                        if !stop.clientPhone.isEmpty {
                            Text(stop.clientPhone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Recipients").textCase(nil)
        }
    }

    // MARK: - Tag Filtering

    private func tagsForStop(_ stop: RouteStop) -> [String] {
        allClients.first { $0.id == stop.clientID }?.tags ?? []
    }

    private var availableTags: [String] {
        Array(Set(stops.flatMap { tagsForStop($0) })).sorted()
    }

    private func stopsForTag(_ tag: String) -> [RouteStop] {
        stops.filter { tagsForStop($0).contains(tag) }
    }

    private func toggleTag(_ tag: String) {
        let tagIDs = Set(stopsForTag(tag).map { $0.id })
        if tagIDs.isSubset(of: includedIDs) {
            includedIDs.subtract(tagIDs)
        } else {
            includedIDs.formUnion(tagIDs)
        }
    }

    @ViewBuilder
    private var tagFilterSection: some View {
        if !availableTags.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableTags, id: \.self) { tag in
                            let tagIDs = Set(stopsForTag(tag).map { $0.id })
                            let allSelected = tagIDs.isSubset(of: includedIDs)
                            Button { toggleTag(tag) } label: {
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(allSelected ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(allSelected ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } header: {
                Text("Filter by Tag").textCase(nil)
            } footer: {
                Text("Tap a tag to select or deselect all clients with that tag.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Send Logic

    private func startSequentialSend() {
        sendQueue = selectedStops
        sendStarted = true
        showingComposer = true
    }

    private func startGroupSend() {
        groupPhones = selectedStops.map { $0.clientPhone }
        sendStarted = true
        showingComposer = true
    }

    private func advanceSendQueue() {
        guard sendStarted else { return }

        // Group text path — single compose window; we're done
        if !groupPhones.isEmpty {
            groupPhones = []
            dismiss()
            return
        }

        // Individual path — advance to next stop
        if !sendQueue.isEmpty { sendQueue.removeFirst() }
        if sendQueue.isEmpty {
            dismiss()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showingComposer = true
            }
        }
    }
}
