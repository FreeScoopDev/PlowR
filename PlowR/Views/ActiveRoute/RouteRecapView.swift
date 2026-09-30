import SwiftUI
import SwiftData
import MapKit

struct RouteRecapView: View {
    let route: PlowRoute
    let stops: [RouteStop]
    let allClients: [Client]
    let onEndRoute: () -> Void
    /// The run being recapped (ActiveRouteStore.runID), so editing a stop's
    /// services updates that run's Service Log record.
    var runID: UUID?
    /// When the run started: which day's visit a stop never completed is.
    var runStartedAt: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var editingStop: RouteStop?

    private var completedStops: [RouteStop] {
        stops.filter { $0.actualMinutes > 0 || !$0.completedServiceIDs.isEmpty }
    }

    private var skippedStops: [RouteStop] {
        stops.filter { $0.actualMinutes == 0 && $0.completedServiceIDs.isEmpty }
    }

    private var geocodedStops: [RouteStop] {
        stops.filter { $0.latitude != 0 && $0.longitude != 0 }
    }

    private var mapCameraPosition: MapCameraPosition {
        guard !geocodedStops.isEmpty else { return .automatic }
        if geocodedStops.count == 1 {
            let s = geocodedStops[0]
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude),
                latitudinalMeters: 1200, longitudinalMeters: 1200
            ))
        }
        guard let bounds = CoordinateBounds(latitudes: geocodedStops.map(\.latitude),
                                            longitudes: geocodedStops.map(\.longitude)) else {
            return .automatic
        }
        return .region(bounds.region())
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection

                if !geocodedStops.isEmpty {
                    mapSection
                }

                if !completedStops.isEmpty {
                    Section("Completed Stops") {
                        ForEach(Array(completedStops.enumerated()), id: \.element.id) { idx, stop in
                            stopRow(stop, index: idx + 1, completed: true)
                        }
                    }
                }

                if !skippedStops.isEmpty {
                    Section("Not Serviced") {
                        ForEach(Array(skippedStops.enumerated()), id: \.element.id) { idx, stop in
                            stopRow(stop, index: completedStops.count + idx + 1, completed: false)
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        onEndRoute()
                    } label: {
                        Label("End Route", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionStyle(.green)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .navigationTitle("Route Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
        .sheet(item: $editingStop) { stop in
            StopServiceRecorderView(
                stop: stop,
                client: allClients.first { $0.id == stop.clientID },
                operatorID: route.operatorID,
                runID: runID,
                stopStartedAt: runStartedAt
            )
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            StatTileRow {
                StatTile(value: "\(completedStops.count)", label: "Serviced", color: .green)
                if skippedStops.count > 0 {
                    StatTile(value: "\(skippedStops.count)", label: "Skipped", color: .orange)
                }
                let totalMin = stops.reduce(0) { $0 + $1.actualMinutes }
                if totalMin > 0 {
                    let h = totalMin / 60, m = totalMin % 60
                    let label = h > 0 ? "\(h)h \(m)m" : "\(m)m"
                    StatTile(value: label, label: "On Route", color: .blue)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Section {
            Map(position: .constant(mapCameraPosition)) {
                ForEach(geocodedStops, id: \.id) { stop in
                    let isDone = stop.actualMinutes > 0 || !stop.completedServiceIDs.isEmpty
                    Annotation("", coordinate: CLLocationCoordinate2D(
                        latitude: stop.latitude,
                        longitude: stop.longitude
                    )) {
                        recapPin(isDone: isDone)
                    }
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            .allowsHitTesting(false)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    private func recapPin(isDone: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isDone ? Color.green : Color(.systemGray3))
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            Image(systemName: isDone ? "checkmark" : "minus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Stop Row

    private func stopRow(_ stop: RouteStop, index: Int, completed: Bool) -> some View {
        Button {
            editingStop = stop
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(completed ? Color.green.opacity(0.15) : Color(.systemGray5))
                        .frame(width: 32, height: 32)
                    Image(systemName: completed ? "checkmark" : "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(completed ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.clientName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !stop.clientAddress.isEmpty {
                        Text(stop.clientAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if !stop.completedServiceIDs.isEmpty {
                        Text("\(stop.completedServiceIDs.count) service\(stop.completedServiceIDs.count == 1 ? "" : "s")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Text("No services")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if stop.actualMinutes > 0 {
                        Text("\(stop.actualMinutes) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "pencil.circle")
                    .foregroundStyle(.blue.opacity(0.7))
                    .font(.subheadline)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
