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
    @State private var clientToDelete: Client?
    @State private var statsClient: Client?
    @State private var sortOption: ClientSortOption = .name
    @State private var filterOption: ClientFilterOption = .all
    @State private var activeTagFilter: String? = nil

    private var availableTags: [String] {
        let mine = allClients.filter { $0.operatorID == authManager.userID }
        return Array(Set(mine.flatMap { $0.tags })).sorted()
    }

    private var isFiltered: Bool { sortOption != .name || filterOption != .all || activeTagFilter != nil }

    private func outstandingBalance(for client: Client) -> Double {
        allProposals
            .filter { $0.clientID == client.id.uuidString && $0.isInvoice && $0.invoicePaidAt == nil }
            .reduce(0) { $0 + $1.total }
    }

    private func hasOverdue(for client: Client) -> Bool {
        allProposals.contains {
            $0.clientID == client.id.uuidString && $0.invoiceStatus == .overdue
        }
    }

    var clients: [Client] {
        let base = allClients.filter { $0.operatorID == authManager.userID }

        let filtered: [Client]
        switch filterOption {
        case .all:       filtered = base
        case .active:    filtered = base.filter { $0.totalVisits > 0 }
        case .noHistory: filtered = base.filter { $0.totalVisits == 0 }
        }

        let tagFiltered = activeTagFilter.map { tag in filtered.filter { $0.tags.contains(tag) } } ?? filtered

        return tagFiltered.sorted { a, b in
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

    var body: some View {
        Group {
            if clients.isEmpty {
                ContentUnavailableView(
                    filterOption == .all && activeTagFilter == nil ? "No Clients Yet" : "No Clients Match",
                    systemImage: filterOption == .all && activeTagFilter == nil ? "person.badge.plus" : "line.3.horizontal.decrease.circle",
                    description: Text(filterOption == .all && activeTagFilter == nil
                        ? "Add your first client to get started."
                        : "Try adjusting your filter.")
                )
            } else {
                List {
                    ForEach(clients) { client in
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                clientToDelete = client
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddClient = true } label: {
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
            Button("Delete", role: .destructive) {
                if let client = clientToDelete {
                    modelContext.delete(client)
                    clientToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { clientToDelete = nil }
        } message: {
            Text("This client will be removed from all routes.")
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
        return Color(red: 0.118, green: 0.227, blue: 0.541)
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 4, height: 48)

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
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    ClientListView()
        .environment(AuthManager())
        .modelContainer(for: Client.self, inMemory: true)
}
