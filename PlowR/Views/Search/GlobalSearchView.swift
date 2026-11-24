import SwiftUI
import SwiftData
import Combine
import CoreData

/// Home's Search: one search across clients, documents, routes and
/// Service Log jobs (`AppSearch`), grouped by kind, at most five of each
/// with Show All for the rest. A result opens the screen that already
/// shows it, pushed on Home's stack, with that screen's own gates.
///
/// The records are fetched once when the page opens (and again when the
/// store saves or iCloud brings changes), not with `@Query`s that would
/// re-run on every keystroke; the search runs in memory a moment after
/// typing stops.
struct GlobalSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager

    @State private var query = ""
    @State private var isSearching = false
    @State private var clients: [Client] = []
    @State private var documents: [Proposal] = []
    @State private var routes: [PlowRoute] = []
    @State private var records: [ServiceRecord] = []
    @State private var results = AppSearch.Results()
    /// The query `results` answer, so No Matches waits for the search.
    @State private var searchedQuery = ""

    var body: some View {
        List {
            if !results.clients.isEmpty {
                Section(title: "Clients") {
                    ForEach(AppSearch.shown(results.clients)) { clientLink($0) }
                    if AppSearch.hasMore(results.clients) {
                        showAll(results.clients.count) {
                            SearchShowAllList(title: "Clients", items: results.clients) { clientLink($0) }
                        }
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }
            if !results.documents.isEmpty {
                Section(title: "Documents") {
                    ForEach(AppSearch.shown(results.documents)) { documentLink($0) }
                    if AppSearch.hasMore(results.documents) {
                        showAll(results.documents.count) {
                            SearchShowAllList(title: "Documents", items: results.documents) { documentLink($0) }
                        }
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }
            if !results.routes.isEmpty {
                Section(title: "Routes") {
                    ForEach(AppSearch.shown(results.routes)) { routeLink($0) }
                    if AppSearch.hasMore(results.routes) {
                        showAll(results.routes.count) {
                            SearchShowAllList(title: "Routes", items: results.routes) { routeLink($0) }
                        }
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }
            if !results.records.isEmpty {
                Section(title: "Work") {
                    ForEach(AppSearch.shown(results.records)) { recordLink($0) }
                    if AppSearch.hasMore(results.records) {
                        showAll(results.records.count) {
                            SearchShowAllList(title: "Work", items: results.records) { recordLink($0) }
                        }
                    }
                }
                .listRowBackground(PlowRColor.surface)
            }
        }
        .plowRGrouped()
        .overlay {
            if results.isEmpty && !ClientSearch.words(searchedQuery).isEmpty {
                ContentUnavailableView.search(text: ClientSearch.query(searchedQuery))
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearching,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search Clients, Documents, Routes, Work")
        .task {
            load()
            isSearching = true
        }
        .task(id: query) {
            // Typing on cancels this wait, so the search runs once typing stops.
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            search()
        }
        // A record opened from here can be deleted there: fetch afresh, so
        // the results never hold a deleted one. Combine's receive(on:) keeps
        // a poster off the main thread from waiting for this screen.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)
            .merge(with: NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange))
            .receive(on: DispatchQueue.main)) { _ in
            load()
            search()
        }
    }

    // MARK: - Data

    private func load() {
        let id = authManager.userID
        clients = (try? modelContext.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.operatorID == id }))) ?? []
        documents = (try? modelContext.fetch(FetchDescriptor<Proposal>(predicate: #Predicate { $0.operatorID == id }))) ?? []
        routes = (try? modelContext.fetch(FetchDescriptor<PlowRoute>(predicate: #Predicate { $0.operatorID == id }))) ?? []
        records = (try? modelContext.fetch(FetchDescriptor<ServiceRecord>(predicate: #Predicate { $0.operatorID == id }))) ?? []
    }

    private func search() {
        results = AppSearch.results(query: query, clients: clients, documents: documents, routes: routes,
                                    records: records, operatorID: authManager.userID)
        searchedQuery = query
    }

    private func client(for record: ServiceRecord) -> Client? {
        clients.first { $0.id.uuidString == record.clientID }
    }

    // MARK: - Rows

    private func clientLink(_ client: Client) -> some View {
        NavigationLink { EditClientView(client: client) } label: { SearchClientRow(client: client) }
    }

    private func documentLink(_ document: Proposal) -> some View {
        NavigationLink { ProposalDetailView(proposal: document) } label: { SearchDocumentRow(document: document) }
    }

    private func routeLink(_ route: PlowRoute) -> some View {
        NavigationLink { RouteDetailView(route: route) } label: { SearchRouteRow(route: route) }
    }

    private func recordLink(_ record: ServiceRecord) -> some View {
        NavigationLink {
            ServiceRecordDetailView(record: record, client: client(for: record))
        } label: {
            SearchRecordRow(record: record)
        }
    }

    private func showAll<Destination: View>(_ count: Int,
                                            @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            Text("Show All (\(count))")
                .foregroundStyle(PlowRColor.brand)
        }
    }
}

/// Every result of one kind, pushed from Show All.
private struct SearchShowAllList<Item: Identifiable, Row: View>: View {
    let title: String
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        List {
            Section {
                ForEach(items) { row($0) }
            }
            .listRowBackground(PlowRColor.surface)
        }
        .plowRGrouped()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A client: name and address, inactive ones marked.
private struct SearchClientRow: View {
    let client: Client

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .font(.subheadline.weight(.semibold))
                if !client.address.isEmpty {
                    Text(client.address)
                        .font(.caption)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
            }
            Spacer()
            if !client.isActive {
                StatusChip("Inactive", status: .neutral)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A document: its number (or kind), client, status and total.
private struct SearchDocumentRow: View {
    let document: Proposal

    private var title: String {
        document.isInvoice ? "Invoice \(document.invoiceNumber)" : "Proposal"
    }

    var body: some View {
        let status = document.invoiceStatus
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(document.clientName)
                    .font(.caption)
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.text(document.total))
                    .font(.subheadline.weight(.bold))
                    .wholeValue()
                StatusChip(status.rawValue, systemImage: status.systemImage, status: status.chipStatus)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A route: name and number of stops.
private struct SearchRouteRow: View {
    let route: PlowRoute

    var body: some View {
        let count = route.stops?.count ?? 0
        VStack(alignment: .leading, spacing: 2) {
            Text(route.name)
                .font(.subheadline.weight(.semibold))
            Text(count == 0 ? "No stops yet" : "\(count) stop\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(PlowRColor.inkSecondary)
        }
        .padding(.vertical, 2)
    }
}

/// A job: client, day and what was done.
private struct SearchRecordRow: View {
    let record: ServiceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.clientName.isEmpty ? "Client" : record.clientName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(record.performedAt.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
            Text(ServiceRecordRow.servicesSummary(of: record))
                .font(.caption)
                .foregroundStyle(PlowRColor.inkSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}
