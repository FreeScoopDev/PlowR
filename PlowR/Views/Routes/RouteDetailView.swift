import SwiftUI
import SwiftData

struct RouteDetailView: View {
    let route: PlowRoute
    @Query private var allClients: [Client]

    @State private var showingEditRoute = false
    @State private var isRouteActive = false

    var body: some View {
        List {
            if route.sortedStops.isEmpty {
                ContentUnavailableView(
                    "No Stops",
                    systemImage: "mappin.slash",
                    description: Text("Tap Edit to add stops to this route.")
                )
            } else {
                Section("\(route.sortedStops.count) stop\(route.sortedStops.count == 1 ? "" : "s")") {
                    ForEach(Array(route.sortedStops.enumerated()), id: \.element.id) { index, stop in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.clientName)
                                    .font(.headline)
                                if !stop.clientAddress.isEmpty {
                                    Text(stop.clientAddress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let client = clientFor(stop), client.totalVisits > 0 {
                                    HStack(spacing: 6) {
                                        if let last = client.lastServiceDate {
                                            Label(last.formatted(.dateTime.month(.abbreviated).day()), systemImage: "clock.arrow.circlepath")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if client.averageServiceMinutes > 0 {
                                            Text("· avg \(Int(client.averageServiceMinutes))m")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if client.goalMinutes > 0 {
                                            Text("· goal \(client.goalMinutes)m")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                            Spacer()
                            if let client = clientFor(stop), client.totalVisits > 0 {
                                Text("\(client.totalVisits)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditRoute = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isRouteActive = true
            } label: {
                Text("Start Route")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(route.sortedStops.isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
            .disabled(route.sortedStops.isEmpty)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingEditRoute) {
            EditRouteView(route: route)
        }
        .fullScreenCover(isPresented: $isRouteActive) {
            ActiveRouteView(route: route)
        }
    }

    private func clientFor(_ stop: RouteStop) -> Client? {
        guard !stop.isCustomStop else { return nil }
        return allClients.first { $0.id == stop.clientID }
    }
}
