import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct RouteDetailView: View {
    let route: PlowRoute
    @Environment(ActiveRouteStore.self) private var activeRoute
    @Query private var allClients: [Client]
    @Query private var allServices: [ServiceItem]

    @State private var showingEditRoute = false
    @State private var showingOptimizeConfirm = false
    @State private var isOptimizing = false
    @State private var editingStop: RouteStop?

    // MARK: - Derived

    private var geocodedStops: [(index: Int, stop: RouteStop)] {
        route.sortedStops.enumerated()
            .filter { $0.element.latitude != 0 && $0.element.longitude != 0 }
            .map { (index: $0.offset, stop: $0.element) }
    }

    private var mapCameraPosition: MapCameraPosition {
        guard !geocodedStops.isEmpty else { return .automatic }
        if geocodedStops.count == 1 {
            let s = geocodedStops[0].stop
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude),
                latitudinalMeters: 1200, longitudinalMeters: 1200
            ))
        }
        guard let bounds = CoordinateBounds(latitudes: geocodedStops.map(\.stop.latitude),
                                            longitudes: geocodedStops.map(\.stop.longitude)) else {
            return .automatic
        }
        return .region(bounds.region())
    }

    // MARK: - Body

    var body: some View {
        List {
            if !geocodedStops.isEmpty {
                mapSection
            }

            if route.sortedStops.isEmpty {
                ContentUnavailableView(
                    "No Stops",
                    systemImage: "mappin.slash",
                    description: Text("Tap Edit to add stops to this route.")
                )
            } else {
                Section(stopsSectionHeader) {
                    ForEach(Array(route.sortedStops.enumerated()), id: \.element.id) { index, stop in
                        // A stop opens its page: services, notes, equipment, target time.
                        Button { editingStop = stop } label: {
                            HStack {
                                stopRow(stop: stop, index: index)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
            Button("Optimize (Driving Distances)") {
                Task { await optimizeWithDrivingDistances() }
            }
            Button("Quick Optimize (Straight-Line)") { optimizeRoute() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reorders stops for the shortest route. 'Driving Distances' uses live map data for accuracy but takes a moment.")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if isOptimizing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Calculating driving distances…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Button {
                    activeRoute.start(route)
                } label: {
                    Text("Start Route")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .primaryActionStyle(.blue)
                .disabled(route.sortedStops.isEmpty || isOptimizing)
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingEditRoute) {
            EditRouteView(route: route)
        }
        .sheet(item: $editingStop) { stop in
            StopDetailView(stop: stop, client: clientFor(stop))
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Section {
            Map(position: .constant(mapCameraPosition)) {
                ForEach(geocodedStops, id: \.stop.id) { entry in
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: entry.stop.latitude,
                        longitude: entry.stop.longitude
                    )) {
                        stopPin(number: entry.index + 1, isDone: entry.stop.actualMinutes > 0)
                    }
                }
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            .allowsHitTesting(false)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
        }
    }

    // MARK: - Stop Row

    @ViewBuilder
    private func stopRow(stop: RouteStop, index: Int) -> some View {
        HStack(spacing: 12) {
            stopBadge(number: index + 1, isDone: stop.actualMinutes > 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.clientName)
                    .font(.subheadline.weight(.semibold))
                if !stop.clientAddress.isEmpty {
                    Text(stop.clientAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let client = clientFor(stop), client.totalVisits > 0 {
                    HStack(spacing: 6) {
                        if let last = client.lastServiceDate {
                            Label(last.formatted(.dateTime.month(.abbreviated).day()),
                                  systemImage: "clock.arrow.circlepath")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if client.averageServiceMinutes > 0 {
                            Text("· avg \(Int(client.averageServiceMinutes))m")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // The stop's target, or else its client's goal (RouteFacts).
                let target = RouteFacts.targetMinutes(of: stop, client: clientFor(stop))
                if target > 0 {
                    Label("Target \(RouteFacts.duration(target))", systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                // Expected service icons
                let icons = expectedServiceIcons(for: stop)
                if !icons.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                    }
                }
                // Notes / equipment badges
                if !stop.stopNotes.isEmpty || !stop.equipmentNotes.isEmpty {
                    HStack(spacing: 6) {
                        if !stop.stopNotes.isEmpty {
                            Label("Notes", systemImage: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if !stop.equipmentNotes.isEmpty {
                            Label("Equipment", systemImage: "wrench.and.screwdriver")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if stop.actualMinutes > 0 {
                    Label("\(stop.actualMinutes)m", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else if let client = clientFor(stop), client.totalVisits > 0 {
                    StatusChip("\(client.totalVisits)", color: .blue)
                }
                if stop.latitude == 0 {
                    Image(systemName: "location.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Subviews

    private func stopBadge(number: Int, isDone: Bool) -> some View {
        StopNumberBadge(number: number, isDone: isDone)
    }

    private func stopPin(number: Int, isDone: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isDone ? Color.green : Color.blue)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Helpers

    private func expectedServiceIcons(for stop: RouteStop) -> [String] {
        StopServices.expected(for: stop, client: clientFor(stop)).compactMap { id in
            allServices.first { $0.id.uuidString == id && $0.isActive }.map { iconForService($0.name) }
        }
    }

    private func iconForService(_ name: String) -> String {
        ServiceIcon.symbol(for: name)
    }

    private func clientFor(_ stop: RouteStop) -> Client? {
        guard !stop.isCustomStop else { return nil }
        return allClients.first { $0.id == stop.clientID }
    }

    private var stopsSectionHeader: String {
        let count = route.sortedStops.count
        var label = "\(count) stop\(count == 1 ? "" : "s")"
        let minutes = RouteFacts.estimatedMinutes(of: route.sortedStops, clients: allClients)
        if minutes > 0 { label += " · about \(RouteFacts.duration(minutes))" }
        return label
    }

    // MARK: - Route Optimization

    /// Async nearest-neighbor optimization using actual MKDirections driving times.
    /// Falls back to haversine per segment if a request fails.
    private func optimizeWithDrivingDistances() async {
        var withGPS = route.sortedStops.filter { $0.latitude != 0 }
        let withoutGPS = route.sortedStops.filter { $0.latitude == 0 }
        guard withGPS.count >= 2 else { return }

        isOptimizing = true
        defer { isOptimizing = false }

        var ordered: [RouteStop] = [withGPS.removeFirst()]

        while !withGPS.isEmpty, let last = ordered.last {
            let lastCoord = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
            var bestIdx = withGPS.startIndex
            var bestScore = Double.infinity

            for (idx, candidate) in withGPS.enumerated() {
                let candCoord = CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)
                let req = MKDirections.Request()
                req.source = MKMapItem(placemark: MKPlacemark(coordinate: lastCoord))
                req.destination = MKMapItem(placemark: MKPlacemark(coordinate: candCoord))
                req.transportType = .automobile
                let score: Double
                if let resp = try? await MKDirections(request: req).calculate(),
                   let time = resp.routes.first?.expectedTravelTime {
                    score = time
                } else {
                    score = haversineRadians(last, candidate) * 1_000_000
                }
                if score < bestScore {
                    bestScore = score
                    bestIdx = withGPS.index(withGPS.startIndex, offsetBy: idx)
                }
            }
            ordered.append(withGPS.remove(at: bestIdx))
        }

        for (index, stop) in (ordered + withoutGPS).enumerated() {
            stop.order = index
        }
    }

    /// Fast offline nearest-neighbor using great-circle distance.
    private func optimizeRoute() {
        let stops = route.sortedStops
        let waypoints = stops.map { RouteOptimizer.Waypoint(latitude: $0.latitude, longitude: $0.longitude) }
        let order = RouteOptimizer.nearestNeighborOrder(of: waypoints)
        for (newOrder, origIdx) in order.enumerated() {
            stops[origIdx].order = newOrder
        }
    }

    private func haversineRadians(_ a: RouteStop, _ b: RouteStop) -> Double {
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sinLat = sin(dLat / 2)
        let sinLon = sin(dLon / 2)
        let h = sinLat * sinLat + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinLon * sinLon
        return 2 * asin(sqrt(h))
    }
}
