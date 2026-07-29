import SwiftUI
import SwiftData

struct RouteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allRoutes: [PlowRoute]
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
}

struct RouteRowView: View {
    let route: PlowRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
            Text("\(route.sortedStops.count) stop\(route.sortedStops.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RouteListView()
        .environment(AuthManager())
        .modelContainer(for: [PlowRoute.self, RouteStop.self, Client.self], inMemory: true)
}
