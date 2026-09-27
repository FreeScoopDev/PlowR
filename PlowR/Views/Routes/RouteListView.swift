import SwiftUI
import SwiftData

struct RouteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allRoutes: [PlowRoute]
    @Query private var allClients: [Client]
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
                List {
                    ForEach(routes) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            RouteRowView(route: route)
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
            } else if let client = allClients.first(where: { $0.id == stop.clientID }) {
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

struct RouteRowView: View {
    let route: PlowRoute

    private var completedCount: Int {
        route.sortedStops.filter { $0.actualMinutes > 0 }.count
    }

    private var totalCount: Int { route.sortedStops.count }

    private var subtitleText: String {
        guard totalCount > 0 else { return "No stops" }
        if completedCount == 0 {
            return "\(totalCount) stop\(totalCount == 1 ? "" : "s")"
        }
        return "\(totalCount) stop\(totalCount == 1 ? "" : "s") · \(completedCount)/\(totalCount) complete"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(completedCount > 0 && completedCount < totalCount ? .orange : .secondary)
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
