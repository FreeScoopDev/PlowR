import SwiftUI
import SwiftData

struct ProposalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]
    @Query(sort: \Proposal.createdAt, order: .reverse) private var allProposals: [Proposal]

    @State private var showingClientPicker = false
    @State private var pendingIsInvoice = false
    @State private var creationContext: ProposalCreationContext?
    @State private var proposalToDelete: Proposal?
    @State private var filterStatus: FilterStatus = .all

    enum FilterStatus: String, CaseIterable {
        case all = "All"
        case proposals = "Proposals"
        case invoices = "Invoices"
        case overdue = "Overdue"
    }

    // MARK: - Computed Properties

    private var myProposals: [Proposal] {
        let base = allProposals.filter { $0.operatorID == authManager.userID }
        switch filterStatus {
        case .all:       return base
        case .proposals: return base.filter { !$0.isInvoice }
        case .invoices:  return base.filter { $0.isInvoice }
        case .overdue:   return base.filter { $0.invoiceStatus == .overdue }
        }
    }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }.sorted { $0.name < $1.name }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if myProposals.isEmpty {
                ContentUnavailableView(
                    "No \(filterStatus == .all ? "Proposals" : filterStatus.rawValue) Yet",
                    systemImage: "doc.text",
                    description: Text("Create a proposal for a client to generate a shareable PDF quote.")
                )
            } else {
                List {
                    ForEach(myProposals) { proposal in
                        NavigationLink {
                            ProposalDetailView(proposal: proposal)
                        } label: {
                            ProposalRowView(proposal: proposal)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            invoiceSwipeActions(for: proposal)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                proposalToDelete = proposal
                            } label: {
                                Label("Delete", systemImage: "trash")
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
                if let p = proposalToDelete { modelContext.delete(p); proposalToDelete = nil }
            }
            Button("Cancel", role: .cancel) { proposalToDelete = nil }
        }
        .sheet(isPresented: $showingClientPicker) {
            ClientPickerForProposalView(clients: myClients) { client in
                // Bake isInvoice into the context at selection time — eliminates stale-capture bug
                creationContext = ProposalCreationContext(client: client, isInvoice: pendingIsInvoice)
            }
        }
        .sheet(item: $creationContext) { ctx in
            ProposalBuilderView(client: ctx.client, isInvoiceMode: ctx.isInvoice)
        }
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private func invoiceSwipeActions(for proposal: Proposal) -> some View {
        if !proposal.isInvoice {
            Button {
                convertToInvoice(proposal)
            } label: {
                Label("Invoice", systemImage: "doc.badge.arrow.up")
            }
            .tint(.blue)
        } else if proposal.invoiceStatus == .draft {
            Button {
                proposal.invoiceSentAt = Date()
                if proposal.invoiceDueDate == nil {
                    proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
                }
            } label: {
                Label("Mark Sent", systemImage: "paperplane.fill")
            }
            .tint(.orange)
        } else if proposal.invoiceStatus == .sent || proposal.invoiceStatus == .overdue {
            Button {
                proposal.invoicePaidAt = Date()
            } label: {
                Label("Mark Paid", systemImage: "checkmark.seal.fill")
            }
            .tint(.green)
        }
    }

    // MARK: - Actions

    private func convertToInvoice(_ proposal: Proposal) {
        let count = allProposals.filter { $0.isInvoice && $0.operatorID == authManager.userID }.count
        proposal.invoiceNumber = String(format: "INV-%04d", count + 1)
        proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
    }
}

// MARK: - Supporting Types

struct ProposalCreationContext: Identifiable {
    let id = UUID()
    let client: Client
    let isInvoice: Bool
}

struct ClientPickerForProposalView: View {
    let clients: [Client]
    let onSelect: (Client) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if clients.isEmpty {
                    ContentUnavailableView("No Clients", systemImage: "person.slash",
                        description: Text("Add clients before creating a proposal."))
                } else {
                    List(clients) { client in
                        Button {
                            onSelect(client)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(client.name).font(.headline).foregroundStyle(.primary)
                                Text(client.address).font(.caption).foregroundStyle(.secondary)
                            }
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
            }
        }
    }
}
