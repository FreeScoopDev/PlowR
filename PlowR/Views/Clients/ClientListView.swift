import SwiftUI
import SwiftData

struct ClientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]
    @State private var showingAddClient = false
    @State private var clientToDelete: Client?
    @State private var statsClient: Client?

    var clients: [Client] {
        allClients
            .filter { $0.operatorID == authManager.userID }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if clients.isEmpty {
                ContentUnavailableView(
                    "No Clients Yet",
                    systemImage: "person.badge.plus",
                    description: Text("Add your first client to get started.")
                )
            } else {
                List {
                    ForEach(clients) { client in
                        NavigationLink {
                            EditClientView(client: client)
                        } label: {
                            ClientRowView(client: client, onVisitTap: {
                                statsClient = client
                            })
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
                Button {
                    showingAddClient = true
                } label: {
                    Image(systemName: "plus")
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
    var onVisitTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(client.name)
                .font(.headline)
            Text(client.phone)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !client.address.isEmpty {
                Text(client.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if client.totalVisits > 0 {
                Button {
                    onVisitTap?()
                } label: {
                    HStack(spacing: 6) {
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
        .padding(.vertical, 4)
    }
}

#Preview {
    ClientListView()
        .environment(AuthManager())
        .modelContainer(for: Client.self, inMemory: true)
}
