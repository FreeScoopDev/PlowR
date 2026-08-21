import SwiftUI
import SwiftData

struct RouteDetailView: View {
    let route: PlowRoute
    @Query private var allClients: [Client]

    @State private var showingEditRoute = false
    @State private var isRouteActive = false
    @State private var showingOptimizeConfirm = false

    var body: some View {
        List {
            if route.sortedStops.isEmpty {
                ContentUnavailableView(
                    "No Stops",
                    systemImage: "mappin.slash",
                    description: Text("Tap Edit to add stops to this route.")
                )
            } else {
                Section(stopsSectionHeader) {
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
                Menu {
                    Button { showingEditRoute = true } label: {
                        Label("Edit Route", systemImage: "pencil")
                    }
                    Button { showingOptimizeConfirm = true } label: {
                        Label("Optimize Order", systemImage: "arrow.triangle.swap")
                    }
                    .disabled(route.sortedStops.filter { $0.latitude != 0 }.count < 2)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Optimize Stop Order?", isPresented: $showingOptimizeConfirm, titleVisibility: .visible) {
            Button("Optimize") { optimizeRoute() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reorders stops by shortest travel distance using GPS coordinates. Stops without GPS will be placed last.")
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

    private var estimatedRouteMinutes: Int {
        route.sortedStops.reduce(0) { total, stop in
            guard let client = clientFor(stop), client.averageServiceMinutes > 0 else { return total }
            return total + Int(client.averageServiceMinutes)
        }
    }

    private var stopsSectionHeader: String {
        let count = route.sortedStops.count
        var label = "\(count) stop\(count == 1 ? "" : "s")"
        let est = estimatedRouteMinutes
        if est > 0 {
            let h = est / 60; let m = est % 60
            let timeStr = h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
            label += " · est. \(timeStr)"
        }
        return label
    }

    // MARK: - Route Optimization (nearest-neighbor greedy)

    private func optimizeRoute() {
        var withGPS = route.sortedStops.filter { $0.latitude != 0 }
        let withoutGPS = route.sortedStops.filter { $0.latitude == 0 }
        guard withGPS.count >= 2 else { return }

        var ordered: [RouteStop] = [withGPS.removeFirst()]
        while !withGPS.isEmpty {
            let last = ordered.last!
            let nearestIdx = withGPS.indices.min { i, j in
                haversine(last, withGPS[i]) < haversine(last, withGPS[j])
            }!
            ordered.append(withGPS.remove(at: nearestIdx))
        }

        let all = ordered + withoutGPS
        for (index, stop) in all.enumerated() {
            stop.order = index
        }
    }

    private func haversine(_ a: RouteStop, _ b: RouteStop) -> Double {
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sinLat = sin(dLat / 2)
        let sinLon = sin(dLon / 2)
        let h = sinLat * sinLat + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinLon * sinLon
        return 2 * asin(sqrt(h))
    }
}
