import SwiftUI
import SwiftData

private enum ClientSortOption: String, CaseIterable {
    case name       = "Name"
    case lastService = "Last Service"
    case mostVisits = "Most Visits"
}

private enum ClientFilterOption: String, CaseIterable {
    case all       = "All"
    case active    = "Active"
    case noHistory = "No History"
}

struct ClientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]
    @Query private var allProposals: [Proposal]
    @State private var showingAddClient = false
    @State private var showingContactScanner = false
    @State private var clientToDelete: Client?
    @State private var clientToDeactivate: Client?
    /// What deleting or deactivating the client above touches, worked out
    /// when its prompt opens.
    @State private var removalFootprint = ClientRemoval.Footprint()
    @State private var statsClient: Client?
    @State private var sortOption: ClientSortOption = .name
    @State private var filterOption: ClientFilterOption = .all
    @State private var activeTagFilter: String? = nil
    @State private var searchText = ""

    private var availableTags: [String] {
        let mine = allClients.filter { $0.operatorID == authManager.userID }
        return Array(Set(mine.flatMap { $0.tags })).sorted()
    }

    private var isFiltered: Bool { sortOption != .name || filterOption != .all || activeTagFilter != nil || !searchText.isEmpty }

    private func outstandingBalance(for client: Client) -> Double {
        Payments.owed(allProposals.filter { $0.clientID == client.id.uuidString })
    }

    private func hasOverdue(for client: Client) -> Bool {
        allProposals.contains {
            $0.clientID == client.id.uuidString && $0.invoiceStatus == .overdue
        }
    }

    private func sortedClients(from base: [Client]) -> [Client] {
        base.sorted { a, b in
            switch sortOption {
            case .name:        return a.name < b.name
            case .lastService:
                guard let aDate = a.lastServiceDate else { return false }
                guard let bDate = b.lastServiceDate else { return true }
                return aDate > bDate
            case .mostVisits:  return a.totalVisits > b.totalVisits
            }
        }
    }

    private var filteredClients: [Client] {
        let base = allClients.filter { $0.operatorID == authManager.userID }

        let filtered: [Client]
        switch filterOption {
        case .all:       filtered = base
        case .active:    filtered = base.filter { $0.totalVisits > 0 }
        case .noHistory: filtered = base.filter { $0.totalVisits == 0 }
        }

        let tagFiltered = activeTagFilter.map { tag in filtered.filter { $0.tags.contains(tag) } } ?? filtered

        if searchText.isEmpty { return tagFiltered }
        let q = searchText.lowercased()
        return tagFiltered.filter {
            $0.name.lowercased().contains(q) ||
            $0.address.lowercased().contains(q) ||
            $0.phone.lowercased().contains(q) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var activeClients: [Client] {
        sortedClients(from: filteredClients.filter { $0.isActive })
    }

    var inactiveClients: [Client] {
        sortedClients(from: filteredClients.filter { !$0.isActive })
    }

    var clients: [Client] { activeClients + inactiveClients }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }
    }

    private var totalOutstanding: Double {
        Payments.owed(allProposals.filter { $0.operatorID == authManager.userID })
    }

    private var totalCollected: Double {
        Payments.received(allProposals.filter { $0.operatorID == authManager.userID })
    }

    var body: some View {
        Group {
            if clients.isEmpty && myClients.isEmpty {
                ContentUnavailableView(
                    isFiltered ? "No Clients Match" : "No Clients Yet",
                    systemImage: isFiltered ? "line.3.horizontal.decrease.circle" : "person.badge.plus",
                    description: Text(isFiltered
                        ? "Try adjusting your filter or search."
                        : "Add your first client to get started.")
                )
            } else {
                List {
                    if !myClients.isEmpty {
                        clientSummarySection
                    }
                    ForEach(activeClients) { client in
                        clientRow(client)
                    }
                    if !inactiveClients.isEmpty {
                        Section("Inactive") {
                            ForEach(inactiveClients) { client in
                                clientRow(client)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Clients")
        .searchable(text: $searchText, prompt: "Search clients")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddClient = true
                    } label: {
                        Label("Add Manually", systemImage: "person.badge.plus")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingContactScanner = true
                        } label: {
                            Label("Scan with Camera", systemImage: "camera.viewfinder")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Section("Sort") {
                        ForEach(ClientSortOption.allCases, id: \.self) { option in
                            Button {
                                sortOption = option
                            } label: {
                                if sortOption == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    }
                    Section("Show") {
                        ForEach(ClientFilterOption.allCases, id: \.self) { option in
                            Button {
                                filterOption = option
                            } label: {
                                if filterOption == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    }
                    if !availableTags.isEmpty {
                        Section("Tag") {
                            Button {
                                activeTagFilter = nil
                            } label: {
                                if activeTagFilter == nil {
                                    Label("All Tags", systemImage: "checkmark")
                                } else {
                                    Text("All Tags")
                                }
                            }
                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    activeTagFilter = activeTagFilter == tag ? nil : tag
                                } label: {
                                    if activeTagFilter == tag {
                                        Label(tag, systemImage: "checkmark")
                                    } else {
                                        Text(tag)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: isFiltered
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddClient) {
            AddClientView()
        }
        .sheet(isPresented: $showingContactScanner) {
            ContactScannerView()
        }
        .sheet(item: $statsClient) { client in
            ClientVisitSummaryView(client: client)
        }
        .confirmationDialog(
            "Delete \(clientToDelete?.name ?? "this client")?",
            isPresented: Binding(
                get: { clientToDelete != nil },
                set: { if !$0 { clientToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let client = clientToDelete {
                if removalFootprint.hasRecords {
                    Button("Delete, Keep Records") { delete(client, keepingRecords: true) }
                    Button("Delete Everything", role: .destructive) { delete(client, keepingRecords: false) }
                } else {
                    // Nothing was listed to keep; anything that turns up meanwhile stays.
                    Button("Delete", role: .destructive) { delete(client, keepingRecords: true) }
                }
                if client.isActive {
                    Button("Mark Inactive Instead") {
                        ClientRemoval.setActive(false, for: client, in: modelContext)
                        clientToDelete = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { clientToDelete = nil }
        } message: {
            Text(ClientRemoval.deleteMessage(for: removalFootprint, isActive: clientToDelete?.isActive ?? false))
        }
        .confirmationDialog(
            "Mark \(clientToDeactivate?.name ?? "this client") Inactive?",
            isPresented: Binding(
                get: { clientToDeactivate != nil },
                set: { if !$0 { clientToDeactivate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let client = clientToDeactivate {
                Button("Mark Inactive", role: .destructive) {
                    ClientRemoval.setActive(false, for: client, in: modelContext)
                    clientToDeactivate = nil
                }
            }
            Button("Cancel", role: .cancel) { clientToDeactivate = nil }
        } message: {
            Text(ClientRemoval.deactivateMessage(for: removalFootprint))
        }
    }

    // MARK: - Summary Section

    private var clientSummarySection: some View {
        Section {
            StatTileRow {
                StatTile(
                    value: "\(myClients.filter { $0.isActive }.count)",
                    label: "Active",
                    color: .blue
                )
                if totalOutstanding > 0 {
                    StatTile(
                        value: totalOutstanding.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                        label: "Outstanding",
                        color: .orange
                    )
                }
                if totalCollected > 0 {
                    StatTile(
                        value: totalCollected.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                        label: "Collected",
                        color: .green
                    )
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Client Row

    @ViewBuilder
    private func clientRow(_ client: Client) -> some View {
        NavigationLink {
            EditClientView(client: client)
        } label: {
            ClientRowView(
                client: client,
                outstandingBalance: outstandingBalance(for: client),
                isOverdue: hasOverdue(for: client),
                onVisitTap: { statsClient = client }
            )
        }
        .contextMenu {
            Button {
                statsClient = client
            } label: {
                Label("View Visit History", systemImage: "chart.bar.fill")
            }
            Button {
                toggleActive(client)
            } label: {
                Label(client.isActive ? "Mark Inactive" : "Mark Active",
                      systemImage: client.isActive ? "archivebox" : "person.crop.circle.badge.checkmark")
            }
            Divider()
            Button(role: .destructive) {
                askToDelete(client)
            } label: {
                Label("Delete Client", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                askToDelete(client)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                toggleActive(client)
            } label: {
                Label(client.isActive ? "Inactive" : "Active",
                      systemImage: client.isActive ? "archivebox" : "person.crop.circle")
            }
            .tint(client.isActive ? .secondary : .blue)
        }
    }
}

// MARK: - Deleting and deactivating

extension ClientListView {
    private func askToDelete(_ client: Client) {
        removalFootprint = ClientRemoval.footprint(of: client, in: modelContext)
        clientToDelete = client
    }

    private func delete(_ client: Client, keepingRecords: Bool) {
        ClientRemoval.delete(client, keepingRecords: keepingRecords, in: modelContext)
        clientToDelete = nil
    }

    /// Mark Inactive takes the client off their routes, so it asks first
    /// when they're on one. Mark Active just does it: it doesn't put them
    /// back on routes.
    private func toggleActive(_ client: Client) {
        guard client.isActive else {
            ClientRemoval.setActive(true, for: client, in: modelContext)
            return
        }
        removalFootprint = ClientRemoval.footprint(of: client, in: modelContext)
        if removalFootprint.routeNames.isEmpty {
            ClientRemoval.setActive(false, for: client, in: modelContext)
        } else {
            clientToDeactivate = client
        }
    }
}

// MARK: - Client Row

struct ClientRowView: View {
    let client: Client
    var outstandingBalance: Double = 0
    var isOverdue: Bool = false
    var onVisitTap: (() -> Void)? = nil

    private var accentColor: Color {
        if isOverdue { return .red }
        if outstandingBalance > 0 { return .orange }
        if client.isComped { return .purple }
        return PlowRColor.navy
    }

    var body: some View {
        HStack(spacing: 12) {
            AccentBar(color: accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(client.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !client.phone.isEmpty {
                    Text(client.phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if client.totalVisits > 0 {
                    Button {
                        onVisitTap?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            if let last = client.lastServiceDate {
                                Text(last, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("· \(client.totalVisits) visit\(client.totalVisits == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                badgeRow
                if !client.address.isEmpty {
                    Text(client.address)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: 4) {
            if client.isComped {
                badge("COMP", color: .purple)
            }
            if !client.preferredPayment.isEmpty {
                badge(client.preferredPayment.capitalized, color: .blue)
            }
            if client.skipNotificationPrompt {
                Image(systemName: "bell.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if isOverdue {
                badge("Overdue", color: .red)
            } else if outstandingBalance > 0 {
                badge(String(format: "$%.0f due", outstandingBalance), color: .orange)
            }
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        StatusChip(label, color: color)
    }
}

#Preview {
    ClientListView()
        .environment(AuthManager())
        .modelContainer(for: Client.self, inMemory: true)
}
