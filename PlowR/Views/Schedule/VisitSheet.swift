import SwiftUI
import SwiftData

/// A visit's field workflow, opened by tapping a visit on the Schedule or on
/// Home's Today: what it is and where it stands, and big buttons for
/// Complete, Record Services and Complete & Invoice. What shows, and why
/// anything doesn't, is `VisitActions`; everything is recorded and billed
/// through the paths Complete and a route stop share (`ServiceLog`). The
/// sheet stays open after an action and shows the new state.
struct VisitSheet: View {
    let visit: ScheduledVisit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.access) private var access
    @Environment(ActiveRouteStore.self) private var activeRoute
    @Query private var allClients: [Client]
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]
    @Query private var allServices: [ServiceItem]

    @State private var gate: ProGate?
    @State private var recorder: RecorderRequest?
    @State private var editingVisit = false
    /// A draft made by Complete & Invoice, opened once the recorder has gone.
    @State private var pendingInvoice: Proposal?
    @State private var invoiceToShow: Proposal?
    @State private var nothingToBill: String?
    /// Bumped after anything here changes the record, which no query watches.
    @State private var revision = 0

    /// Record Services opened from here, and how.
    private struct RecorderRequest: Identifiable {
        let id = UUID()
        let invoiceOnSave: Bool
    }

    private var client: Client? {
        allClients.first { $0.id.uuidString == visit.clientID && $0.operatorID == visit.operatorID }
    }

    private var isGone: Bool { visit.isDeleted || visit.modelContext == nil }

    var body: some View {
        NavigationStack {
            Group {
                if isGone {
                    ContentUnavailableView("Visit Deleted", systemImage: PlowRSymbol.schedule.name)
                } else {
                    content
                }
            }
            .background(PlowRColor.ground)
            .navigationTitle("Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .proGateSheet($gate)
        .sheet(item: $recorder, onDismiss: {
            revision += 1
            if let pendingInvoice {
                self.pendingInvoice = nil
                invoiceToShow = pendingInvoice
            }
        }, content: { request in
            StopServiceRecorderView(visit: visit, client: client, operatorID: visit.operatorID,
                                    invoiceOnSave: request.invoiceOnSave) { outcome in
                switch outcome {
                case .saved: break
                case .invoiced(let proposal): pendingInvoice = proposal
                case .nothingToBill(let message): nothingToBill = message
                }
            }
        })
        .sheet(isPresented: $editingVisit, onDismiss: { revision += 1 }, content: {
            AddVisitView(editing: visit)
        })
        .sheet(item: $invoiceToShow, onDismiss: { revision += 1 }, content: { invoice in
            NavigationStack {
                ProposalDetailView(proposal: invoice)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { invoiceToShow = nil }
                        }
                    }
            }
        })
        .alert("Work Saved", isPresented: Binding(get: { nothingToBill != nil },
                                                 set: { if !$0 { nothingToBill = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(nothingToBill ?? "")
        }
    }

    // MARK: - Content

    private var content: some View {
        // Read so the facts are worked out again after an action.
        let _ = revision
        let client = client
        let plan = VisitActions(VisitActions.facts(for: visit, client: client, canEdit: access.canEdit,
                                                   in: modelContext))
        return ScrollView {
            VStack(alignment: .leading, spacing: PlowRLayout.space4) {
                details(client: client, plan: plan)
                notes(plan)
                actions(plan, client: client)
            }
            .padding(PlowRLayout.space4)
        }
    }

    private func details(client: Client?, plan: VisitActions) -> some View {
        PlowRCard {
            VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                Text(client?.name ?? visit.clientName)
                    .font(PlowRFont.title)
                    .foregroundStyle(PlowRColor.ink)
                if !visit.clientAddress.isEmpty {
                    Text(visit.clientAddress)
                        .font(.subheadline)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
                Text(visit.scheduledDate.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(PlowRColor.inkSecondary)
                chips(plan)
                if !visit.visitReason.isEmpty {
                    LabeledContent("Reason", value: visit.visitReason)
                        .font(.subheadline)
                }
                if !expectedNames.isEmpty {
                    LabeledContent("Expected", value: OneTapServices.englishList(expectedNames))
                        .font(.subheadline)
                }
                if !visit.notes.isEmpty {
                    Text(visit.notes)
                        .font(.subheadline)
                        .foregroundStyle(PlowRColor.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PlowRLayout.space4)
        }
    }

    /// Status, repeating, After Hours and Invoiced. Invoiced is the plan's
    /// invoice (VisitActions: the visit's, else the record's, and it must
    /// exist), the same one View Invoice opens.
    private func chips(_ plan: VisitActions) -> some View {
        FlowChips {
            StatusChip(visit.status.rawValue, systemImage: visit.status.systemImage, status: visit.status.chipStatus)
            if visit.isRecurring {
                StatusChip("Repeats", systemImage: "arrow.triangle.2.circlepath", status: .scheduled)
            }
            if visit.isAfterHours {
                AfterHoursChip()
            }
            if plan.invoiceNumber != nil {
                StatusChip("Invoiced", systemImage: PlowRSymbol.document.name, status: .done)
            }
        }
    }

    /// The visit's expected services by name, in the catalog's order.
    private var expectedNames: [String] {
        let wanted = Set(visit.expectedServiceIDs)
        return allServices.filter { wanted.contains($0.id.uuidString) }
            .sorted { ServiceLog.catalogOrder($0, $1) }
            .map(\.name)
    }

    /// Why actions are missing, the inactive client, the running route.
    @ViewBuilder
    private func notes(_ plan: VisitActions) -> some View {
        let lines = [plan.inactiveNote, runningRouteNote].compactMap { $0 } + plan.reasons
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
            }
        }
    }

    /// When the running route has a stop still to do for this client: one
    /// line. The actions stay: completing here, the stop shares the record
    /// (ServiceLog.visitForStop).
    private var runningRouteNote: String? {
        guard activeRoute.isActive, visit.status == .scheduled, let route = activeRoute.route else { return nil }
        let stops = activeRoute.sortedStops
        let pending = stops.indices.contains { index in
            index >= activeRoute.currentStopIndex && stops[index].clientID.uuidString == visit.clientID
        }
        guard pending else { return nil }
        return "\(client?.name ?? visit.clientName) is a stop on \(route.name), running now: "
            + "complete it there to keep its times."
    }

    // MARK: - Actions

    private func actions(_ plan: VisitActions, client: Client?) -> some View {
        VStack(spacing: PlowRLayout.space3) {
            ForEach(plan.actions, id: \.self) { action in
                actionButton(action, plan: plan, client: client)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: VisitActions.Action, plan: VisitActions, client: Client?) -> some View {
        let title = plan.title(of: action)
        let label = Label(title, systemImage: symbol(of: action))
            .frame(maxWidth: .infinity, minHeight: PlowRLayout.gloveTapTarget)
        switch action {
        case .viewInvoice:
            if let invoice = currentInvoice {
                NavigationLink { ProposalDetailView(proposal: invoice) } label: { label }
                    .buttonStyle(.plowRSecondary)
            }
        case .openClient:
            if let client {
                NavigationLink { EditClientView(client: client) } label: { label }
                    .buttonStyle(.plowRSecondary)
            }
        default:
            let button = Button {
                if plan.isGated(action) {
                    $gate.unless(ProGate.edit(access)) { run(action) }
                } else {
                    run(action)
                }
            } label: { label }
            if plan.primary == action {
                button.buttonStyle(.plowRAction)
            } else {
                button.buttonStyle(.plowRSecondary)
            }
        }
    }

    private func symbol(of action: VisitActions.Action) -> String {
        switch action {
        case .complete: PlowRSymbol.complete.name
        case .recordServices, .editServices: PlowRSymbol.services.name
        case .completeAndInvoice, .invoiceWork: "doc.badge.plus"
        case .viewInvoice: PlowRSymbol.document.name
        case .editVisit: "pencil"
        case .openClient: PlowRSymbol.client.name
        }
    }

    /// The invoice the visit's work is on, as VisitActions finds it.
    private var currentInvoice: Proposal? {
        ServiceLog.invoice(ofVisit: visit, in: modelContext)
            ?? ServiceLog.record(forKey: ServiceLog.visitKey(visit.id), in: modelContext)
                .flatMap { ServiceLog.invoice(of: $0, in: modelContext) }
    }

    private func run(_ action: VisitActions.Action) {
        switch action {
        case .complete:
            complete()
        case .recordServices, .editServices:
            recorder = RecorderRequest(invoiceOnSave: false)
        case .completeAndInvoice, .invoiceWork:
            recorder = RecorderRequest(invoiceOnSave: true)
        case .editVisit:
            editingVisit = true
        case .viewInvoice, .openClient:
            break
        }
    }

    /// The same as Schedule's Complete: `ServiceLog.complete`, never the
    /// status by hand.
    private func complete() {
        guard visit.status == .scheduled else { return }
        ServiceLog.complete(visit, among: allVisits, in: modelContext)
        Haptics.success()
        revision += 1
    }
}

/// Chips that wrap onto a second line when there isn't room.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PlowRLayout.space2) { content }
            VStack(alignment: .leading, spacing: PlowRLayout.space2) { content }
        }
    }
}
