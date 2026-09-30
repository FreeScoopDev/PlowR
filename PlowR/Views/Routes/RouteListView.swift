import SwiftUI
import SwiftData

struct RouteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allRoutes: [PlowRoute]
    @Query private var allClients: [Client]
    @Query private var records: [ServiceRecord]
    @State private var showingCreateRoute = false
    @State private var routeToDelete: PlowRoute?

    var routes: [PlowRoute] {
        allRoutes
            .filter { $0.operatorID == authManager.userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if routes.isEmpty {
                ContentUnavailableView(
                    "No Routes Yet",
                    systemImage: "map.badge.plus",
                    description: Text("Create a route to organize your stops.")
                )
            } else {
                let lastRuns = RouteFacts.lastRuns(in: records)
                List {
                    ForEach(routes) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            RouteRowView(route: route, clients: allClients,
                                         lastRun: lastRuns[route.id.uuidString])
                        }
                        .contextMenu {
                            Button {
                                duplicateRoute(route)
                            } label: {
                                Label("Duplicate Route", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) {
                                routeToDelete = route
                            } label: {
                                Label("Delete Route", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                routeToDelete = route
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Routes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateRoute = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateRoute) {
            CreateRouteView()
        }
        .confirmationDialog(
            "Delete \"\(routeToDelete?.name ?? "this route")\"?",
            isPresented: Binding(
                get: { routeToDelete != nil },
                set: { if !$0 { routeToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let route = routeToDelete {
                    modelContext.delete(route)
                    routeToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { routeToDelete = nil }
        } message: {
            Text("This will permanently delete the route and all its stops.")
        }
    }

    private func duplicateRoute(_ route: PlowRoute) {
        let copy = PlowRoute(name: "\(route.name) (Copy)", operatorID: route.operatorID)
        modelContext.insert(copy)
        for (index, stop) in route.sortedStops.enumerated() {
            if stop.isCustomStop {
                let stopCopy = RouteStop(order: index, customName: stop.clientName,
                                        customAddress: stop.clientAddress, customPhone: stop.clientPhone)
                stopCopy.stopNotes = stop.stopNotes
                stopCopy.equipmentNotes = stop.equipmentNotes
                stopCopy.targetMinutes = stop.targetMinutes
                stopCopy.route = copy
                modelContext.insert(stopCopy)
            } else if let client = allClients.first(where: { $0.id == stop.clientID }), client.isActive {
                // A copy is a new route: inactive clients stay off it, as off every new route.
                let stopCopy = RouteStop(order: index, client: client)
                stopCopy.stopNotes = stop.stopNotes
                stopCopy.equipmentNotes = stop.equipmentNotes
                stopCopy.targetMinutes = stop.targetMinutes
                stopCopy.route = copy
                modelContext.insert(stopCopy)
            }
        }
    }
}

/// A route in the list: a map icon coloured by how its run stands, its
/// name, its stops and about how long they take, and when it last ran.
/// It used to be a name, a stop count and a grey bar.
struct RouteRowView: View {
    let route: PlowRoute
    let clients: [Client]
    let lastRun: Date?
    @Environment(ActiveRouteStore.self) private var activeRoute

    private var run: RouteRunSummary {
        RouteRunSummary(stops: route.sortedStops, isRunning: activeRoute.route?.id == route.id)
    }

    private var color: Color {
        run.isRunning ? .orange : (run.isDone ? .green : .blue)
    }

    private var stopsText: String {
        let count = run.total
        guard count > 0 else { return "No stops yet" }
        var text = "\(count) stop\(count == 1 ? "" : "s")"
        let minutes = RouteFacts.estimatedMinutes(of: route.sortedStops, clients: clients)
        if minutes > 0 { text += " · about \(RouteFacts.duration(minutes))" }
        return text
    }

    private var statusText: String {
        if run.isRunning { return "Running · \(run.done) of \(run.total) done" }
        guard let lastRun else { return "Not run yet" }
        return RouteFacts.lastRunText(lastRun)
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: run.isRunning ? "map.fill" : "map", color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(stopsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(run.isRunning ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RouteListView()
        .environment(AuthManager())
        .environment(ActiveRouteStore.shared)
        .modelContainer(for: [PlowRoute.self, RouteStop.self, Client.self], inMemory: true)
}
