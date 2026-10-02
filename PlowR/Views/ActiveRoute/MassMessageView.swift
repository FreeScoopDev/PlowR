import SwiftData
import SwiftUI
import MessageUI

struct MassMessageView: View {
    let stops: [RouteStop]
    let allClients: [Client]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var includedIDs: Set<UUID>
    @State private var messageText = ""
    /// Texting the selected clients one at a time.
    @State private var run: MessageRun?
    @State private var groupPhones: [String] = []
    /// The clients the group text is going to, for their Timeline.
    @State private var groupClientIDs: [UUID] = []
    @State private var showingComposer = false
    @State private var showingGroupWarning = false
    /// Why sending one at a time stopped, and who's left.
    @State private var stoppedNote: String?

    /// What the texts are kept as on each client's Timeline.
    private let kind: TextLog.Kind
    private let presets: [(String, String)]

    static let routePresets: [(String, String)] = [
        ("Coming Today",  "Just letting you know we'll be at your property today."),
        ("On My Way",     "I'll be at your property soon."),
        ("Move Vehicles", "Please move any vehicles from the driveway when you get a chance."),
        ("Running Late",  "Running slightly behind schedule — I'll be there shortly, thank you for your patience."),
        ("Weather Delay", "Weather is slowing things down a bit. I'm working safely and will be there soon."),
        ("Almost Done",   "I'm nearly finished and will be on my way shortly.")
    ]

    /// `presets` and `kind`: a screen texting for its own reason (the storm
    /// card) brings its own quick texts, and what its texts are kept as.
    init(stops: [RouteStop], allClients: [Client], presets: [(String, String)] = MassMessageView.routePresets,
         kind: TextLog.Kind = .routeMessage) {
        self.presets = presets
        self.kind = kind
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
                    .disabled(!canSend || run != nil || !MFMessageComposeViewController.canSendText())
                }
            }
        }
        // Send or Cancel is the only way out: each text's outcome decides
        // what happens next, and a swipe would give none.
        .sheet(isPresented: $showingComposer) {
            Group {
                if !groupPhones.isEmpty {
                    MessageComposer(recipients: groupPhones, body: messageText) { groupFinished($0) }
                } else if let recipient = run?.current {
                    MessageComposer(recipients: [recipient.phone], body: messageText) { textFinished($0) }
                } else {
                    // Nothing to text: never leave an empty sheet up.
                    Color.clear.onAppear { showingComposer = false }
                }
            }
            .interactiveDismissDisabled()
        }
        .alert("Sending Stopped", isPresented: Binding(
            get: { stoppedNote != nil },
            set: { if !$0 { stoppedNote = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(stoppedNote ?? "")
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
        run = MessageRun(selectedStops.map {
            MessageRun.Recipient(id: $0.id, phone: $0.clientPhone, clientID: $0.clientID)
        })
        showingComposer = true
    }

    private func startGroupSend() {
        groupPhones = selectedStops.map { $0.clientPhone }
        groupClientIDs = selectedStops.map(\.clientID)
        showingComposer = true
    }

    /// The group text closed: done if it went, otherwise back to this screen.
    private func groupFinished(_ outcome: MessageOutcome) {
        groupPhones = []
        showingComposer = false
        if outcome == .sent {
            TextLog.record(kind, body: messageText, to: groupClientIDs, in: modelContext)
            dismiss()
        }
    }

    /// One client's text closed: the next client's, the end, or a stop
    /// (MessageRun.step). Cancel used to open the next client's text, with no
    /// way to stop and no record of who had been sent it.
    private func textFinished(_ outcome: MessageOutcome) {
        showingComposer = false
        guard let current = run else { return }
        if let clientID = current.textedClient(outcome) {
            TextLog.record(kind, body: messageText, to: [clientID], in: modelContext)
        }
        let step = MessageRun.step(current, outcome: outcome, selection: includedIDs)
        run = step.run
        includedIDs = step.selection
        stoppedNote = step.note
        switch step.action {
        case .composeNext:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showingComposer = true
            }
        case .close:
            dismiss()
        case .stay:
            break
        }
    }
}

/// Texting clients one at a time, each in its own composer: who's next, and
/// who has been sent it. A text that isn't sent stops the run. Each client's
/// phone is taken when the run starts, so a stop that sync changes or removes
/// meanwhile can't leave an empty composer.
struct MessageRun: Equatable {
    struct Recipient: Equatable {
        var id: UUID
        var phone: String
        /// Their client, for the Timeline (TextLog): taken when the run
        /// starts, as the phone is.
        var clientID: UUID
    }

    private(set) var queue: [Recipient]
    private(set) var sent: [UUID] = []

    init(_ recipients: [Recipient]) {
        queue = recipients
    }

    /// The client whose text is up.
    var current: Recipient? { queue.first }

    /// The client the current text went to, once Messages says it was sent.
    func textedClient(_ outcome: MessageOutcome) -> UUID? {
        outcome == .sent ? current?.clientID : nil
    }

    enum Next: Equatable {
        /// Show the composer for this client.
        case compose(Recipient)
        /// Everyone was texted.
        case finished
        /// A text wasn't sent: these clients haven't been texted.
        case stopped(unsent: [UUID])
    }

    /// The current client's text closed with `outcome`.
    mutating func finish(_ outcome: MessageOutcome) -> Next {
        guard let current = queue.first else { return .finished }
        guard outcome == .sent else { return .stopped(unsent: queue.map(\.id)) }
        sent.append(current.id)
        queue.removeFirst()
        return queue.first.map(Next.compose) ?? .finished
    }

    /// What the screen says when the run stopped.
    func stoppedNote(failed: Bool) -> String {
        let total = sent.count + queue.count
        let why = failed ? "A text didn't send." : "A text was cancelled."
        let rest = queue.count == 1
            ? "The 1 client not texted yet is still selected"
            : "The \(queue.count) clients not texted yet are still selected"
        return "\(why) Sent to \(sent.count) of \(total). \(rest): tap Send to carry on."
    }

    /// What the screen does after one client's text closed.
    struct Step: Equatable {
        /// The run to keep going, or nil when it's over.
        var run: MessageRun?
        /// Who stays selected: never anyone already texted, whatever happens
        /// next, so no Send can text them twice.
        var selection: Set<UUID>
        /// Shown when the run stopped.
        var note: String?
        var action: Action

        enum Action: Equatable {
            case composeNext, close, stay
        }
    }

    /// After `run`'s current client's text closed with `outcome`.
    static func step(_ run: MessageRun, outcome: MessageOutcome, selection: Set<UUID>) -> Step {
        var run = run
        let next = run.finish(outcome)
        let selection = selection.subtracting(run.sent)
        switch next {
        case .compose:
            return Step(run: run, selection: selection, note: nil, action: .composeNext)
        case .finished:
            return Step(run: nil, selection: selection, note: nil, action: .close)
        case .stopped:
            return Step(run: nil, selection: selection, note: run.stoppedNote(failed: outcome == .failed),
                        action: .stay)
        }
    }
}
