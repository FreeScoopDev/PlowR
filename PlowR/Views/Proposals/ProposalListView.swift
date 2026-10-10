import SwiftUI
import SwiftData
import MessageUI

struct ProposalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]
    @Query(sort: \Proposal.createdAt, order: .reverse) private var allProposals: [Proposal]

    @State private var showingClientPicker = false
    @State private var showingBillWork = false
    @State private var pendingIsInvoice = false
    @State private var creationContext: ProposalCreationContext?
    @State private var proposalToDelete: Proposal?
    @State private var filterStatus: FilterStatus = .all
    @State private var reminderProposal: Proposal?

    enum FilterStatus: String, CaseIterable {
        case all = "All"
        case proposals = "Proposals"
        case invoices = "Invoices"
        case overdue = "Overdue"
        case draft = "Draft"
    }

    init(initialFilter: FilterStatus = .all) {
        _filterStatus = State(initialValue: initialFilter)
    }

    // MARK: - Computed Properties

    private var base: [Proposal] {
        allProposals.filter { $0.operatorID == authManager.userID }
    }

    private var myProposals: [Proposal] {
        switch filterStatus {
        case .all:       return base.filter { $0.invoicePaidAt == nil }
        case .proposals: return base.filter { !$0.isInvoice }
        case .invoices:  return base.filter { $0.isInvoice && $0.invoicePaidAt == nil }
        case .overdue:   return base.filter { $0.invoiceStatus == .overdue }
        case .draft:     return base.filter { $0.isInvoice && $0.invoiceStatus == .draft }
        }
    }

    private var archivedProposals: [Proposal] {
        guard filterStatus == .all else { return [] }
        return base.filter { $0.invoicePaidAt != nil }.sorted { ($0.invoicePaidAt ?? .distantPast) > ($1.invoicePaidAt ?? .distantPast) }
    }

    private var outstandingTotal: Double {
        Payments.owed(base)
    }

    private var overdueCount: Int { base.filter { $0.invoiceStatus == .overdue }.count }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }.sorted { $0.name < $1.name }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if myProposals.isEmpty && archivedProposals.isEmpty {
                ContentUnavailableView(
                    "No \(filterStatus == .all ? "Proposals" : filterStatus.rawValue) Yet",
                    systemImage: "doc.text",
                    description: Text("Create a proposal for a client to generate a shareable PDF quote.")
                )
            } else {
                List {
                    if filterStatus == .all && (outstandingTotal > 0 || overdueCount > 0) {
                        summarySection
                    }
                    ForEach(myProposals) { proposal in
                        proposalRow(proposal)
                    }
                    if !archivedProposals.isEmpty {
                        Section("Archived — Paid") {
                            ForEach(archivedProposals) { proposal in
                                proposalRow(proposal)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(filterStatus == .all ? "Documents" : filterStatus.rawValue)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        pendingIsInvoice = false
                        showingClientPicker = true
                    } label: {
                        Label("New Proposal", systemImage: "doc.text")
                    }
                    Button {
                        pendingIsInvoice = true
                        showingClientPicker = true
                    } label: {
                        Label("New Invoice", systemImage: "doc.badge.arrow.up")
                    }
                    Divider()
                    Button {
                        showingBillWork = true
                    } label: {
                        Label("Bill Unbilled Work", systemImage: "tray.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Filter", selection: $filterStatus) {
                        ForEach(FilterStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete this proposal?",
            isPresented: Binding(get: { proposalToDelete != nil }, set: { if !$0 { proposalToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = proposalToDelete { ServiceLog.delete(p, in: modelContext); proposalToDelete = nil }
            }
            Button("Cancel", role: .cancel) { proposalToDelete = nil }
        }
        .sheet(isPresented: $showingBillWork) {
            BillWorkView()
        }
        .sheet(isPresented: $showingClientPicker) {
            ClientPickerForProposalView { client in
                // Bake isInvoice into the context at selection time — eliminates stale-capture bug
                creationContext = ProposalCreationContext(client: client, isInvoice: pendingIsInvoice)
            }
        }
        .sheet(item: $creationContext) { ctx in
            ProposalBuilderView(client: ctx.client, isInvoiceMode: ctx.isInvoice)
        }
        .sheet(item: $reminderProposal) { proposal in
            let phone = myClients.first(where: { $0.id.uuidString == proposal.clientID })?.phone ?? ""
            let body = reminderMessage(for: proposal)
            MessageComposer(recipients: [phone], body: body) { outcome in
                if outcome == .sent, let id = UUID(uuidString: proposal.clientID) {
                    TextLog.record(.invoiceReminder, body: body, to: [id], in: modelContext)
                }
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        Section {
            StatTileRow {
                if outstandingTotal > 0 {
                    StatTile(
                        value: outstandingTotal.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                        label: "Outstanding",
                        color: .orange
                    )
                }
                if overdueCount > 0 {
                    StatTile(value: "\(overdueCount)", label: "Overdue", color: .red)
                }
                let draftCount = base.filter { $0.isInvoice && $0.invoiceStatus == .draft }.count
                if draftCount > 0 {
                    StatTile(value: "\(draftCount)", label: "Drafts", color: .blue)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Proposal Row

    @ViewBuilder
    private func proposalRow(_ proposal: Proposal) -> some View {
        NavigationLink {
            ProposalDetailView(proposal: proposal)
        } label: {
            ProposalRowView(proposal: proposal)
        }
        .contextMenu {
            proposalContextActions(for: proposal)
            Divider()
            Button {
                duplicateProposal(proposal)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                proposalToDelete = proposal
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                proposalToDelete = proposal
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Context Menu Actions

    @ViewBuilder
    private func proposalContextActions(for proposal: Proposal) -> some View {
        if !proposal.isInvoice {
            Button {
                convertToInvoice(proposal)
            } label: {
                Label("Convert to Invoice", systemImage: "doc.badge.arrow.up")
            }
        } else if proposal.invoiceStatus == .draft {
            Button {
                DocumentSent.markSent(proposal, in: modelContext)
            } label: {
                Label("Mark Sent", systemImage: "paperplane.fill")
            }
        } else if proposal.invoiceStatus == .sent || proposal.invoiceStatus == .overdue {
            Button {
                Payments.payInFull(proposal, in: modelContext)
            } label: {
                Label("Mark Paid", systemImage: "checkmark.seal.fill")
            }
            let clientPhone = myClients.first(where: { $0.id.uuidString == proposal.clientID })?.phone ?? ""
            if MFMessageComposeViewController.canSendText() && !clientPhone.isEmpty {
                Button {
                    reminderProposal = proposal
                } label: {
                    Label("Send Reminder", systemImage: "message.fill")
                }
            }
        }
    }

    // MARK: - Actions

    private func convertToInvoice(_ proposal: Proposal) {
        proposal.invoiceNumber = InvoiceNumbering.next(operatorID: proposal.operatorID, in: modelContext)
        proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
    }

    private func reminderMessage(for proposal: Proposal) -> String { proposal.reminderMessage() }

    private func duplicateProposal(_ proposal: Proposal) {
        guard let client = myClients.first(where: { $0.id.uuidString == proposal.clientID }) else { return }
        let copy = Proposal(operatorID: proposal.operatorID, client: client)
        copy.notes = proposal.notes
        copy.disclaimer = proposal.disclaimer
        copy.discountAmount = proposal.discountAmount
        copy.taxRate = proposal.taxRate
        copy.validUntil = proposal.validUntil
        let lineItemCopies = proposal.makeLineItemCopies()
        lineItemCopies.forEach { modelContext.insert($0) }
        copy.lineItems = lineItemCopies
        modelContext.insert(copy)
    }
}

// MARK: - Supporting Types

struct ProposalCreationContext: Identifiable {
    let id = UUID()
    let client: Client
    let isInvoice: Bool
}

struct ClientPickerForProposalView: View {
    let onSelect: (Client) -> Void
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.name) private var allClients: [Client]
    @Environment(\.access) private var access
    @State private var showingAddClient = false
    @State private var gate: ProGate?

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if myClients.isEmpty {
                    ContentUnavailableView(
                        "No Clients Yet",
                        systemImage: "person.badge.plus",
                        description: Text("Add a client to create a proposal.")
                    )
                } else {
                    List(myClients) { client in
                        Button {
                            onSelect(client)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(client.name).font(.headline).foregroundStyle(.primary)
                                if !client.address.isEmpty {
                                    Text(client.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Select Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        $gate.unless(ProGate.addClient(access)) { showingAddClient = true }
                    } label: {
                        Label("New Client", systemImage: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddClient) {
                AddClientView()
            }
            .proGateSheet($gate)
        }
    }
}
