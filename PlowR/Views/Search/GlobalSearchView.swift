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
    /// Focus the field on the first open only: back from a result, the
    /// keyboard stays down over the results scrolled to.
    @State private var hasOpened = false
    /// The field's keyboard: up on the first open, down on scrolling the
    /// results or opening one, so it isn't raised again over them on return.
    @FocusState private var isFieldFocused: Bool
    /// On screen (not under a pushed result): store changes then reload,
    /// after a pause; while hidden they only mark the results stale.
    @State private var isVisible = false
    @State private var isStale = false
    /// Counts store changes seen on screen; each restarts the reload's pause.
    @State private var storeChanges = 0

    var body: some View {
        List {
            if !results.clients.isEmpty {
                Section(title: "Clients") {
                    ForEach(AppSearch.shown(results.clients).filter { !$0.isGoneHere }) { clientLink($0) }
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
                    ForEach(AppSearch.shown(results.documents).filter { !$0.isGoneHere }) { documentLink($0) }
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
                    ForEach(AppSearch.shown(results.routes).filter { !$0.isGoneHere }) { routeLink($0) }
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
                    ForEach(AppSearch.shown(results.records).filter { !$0.isGoneHere }) { recordLink($0) }
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
                // "No Matches", as the Clients list and the client pickers say it.
                NoSearchMatches(query: searchedQuery)
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearching,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search Clients, Documents, Routes, Work")
        .searchFocused($isFieldFocused)
        .scrollDismissesKeyboard(.immediately)
        .task {
            guard !hasOpened else { return }
            hasOpened = true
            load()
            isSearching = true
            isFieldFocused = true
        }
        .onAppear {
            isVisible = true
            // Changed while a result was open (one deleted there, say):
            // fetch afresh now, before the rows are read again.
            if isStale {
                isStale = false
                load()
                search()
            }
        }
        .onDisappear {
            isVisible = false
            isFieldFocused = false
        }
        .task(id: query) {
            // Typing on cancels this wait, so the search runs once typing stops.
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            search()
        }
        // A record opened from here can be deleted there: fetch afresh, so
        // the results never hold a deleted one (the rows also skip one gone
        // meanwhile). Combine's receive(on:) keeps a poster off the main
        // thread from waiting for this screen. A burst of saves or an iCloud
        // import reloads once, 300 ms after the last; hidden, once on return.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)
            .merge(with: NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange))
            .receive(on: DispatchQueue.main)) { _ in
            if isVisible { storeChanges += 1 } else { isStale = true }
        }
        .task(id: storeChanges) {
            guard storeChanges > 0, isVisible else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
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
private struct SearchShowAllList<Item: PersistentModel, Row: View>: View {
    let title: String
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        List {
            Section {
                ForEach(items.filter { !$0.isGoneHere }) { row($0) }
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
        AdaptiveRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .font(.subheadline.weight(.semibold))
                if !client.address.isEmpty {
                    Text(client.address)
                        .font(.caption)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
            }
        } trailing: {
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
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The number alone, as the Documents rows show it; else its kind.
    private var title: String {
        guard document.isInvoice else { return "Proposal" }
        return document.invoiceNumber.isEmpty ? "Invoice" : document.invoiceNumber
    }

    var body: some View {
        let status = document.invoiceStatus
        AdaptiveRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(document.clientName)
                    .font(.caption)
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
        } trailing: {
            // Stacked under the name at accessibility sizes, so lined up left there.
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(Money.text(document.total))
                    .font(.subheadline.weight(.bold))
                    .wholeValue()
                StatusChip(status.rawValue, systemImage: status.systemImage, status: status.chipStatus)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A route: name and number of stops, as the route list says them.
private struct SearchRouteRow: View {
    let route: PlowRoute
    @Environment(ActiveRouteStore.self) private var activeRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(route.name)
                .font(.subheadline.weight(.semibold))
            // Counted as the route list counts: this run's stops while it runs.
            Text(RouteFacts.stopsText(of: route, store: activeRoute))
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
