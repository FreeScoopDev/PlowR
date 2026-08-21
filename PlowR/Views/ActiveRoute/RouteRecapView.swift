import SwiftUI
import SwiftData

struct RouteRecapView: View {
    let route: PlowRoute
    let stops: [RouteStop]
    let allClients: [Client]
    let onEndRoute: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingStop: RouteStop?

    private var completedStops: [RouteStop] {
        stops.filter { $0.actualMinutes > 0 || !$0.completedServiceIDs.isEmpty }
    }

    private var skippedStops: [RouteStop] {
        stops.filter { $0.actualMinutes == 0 && $0.completedServiceIDs.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection

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
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
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
                operatorID: route.operatorID
            )
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(spacing: 24) {
                statCell(value: "\(completedStops.count)", label: "Serviced")
                if skippedStops.count > 0 {
                    statCell(value: "\(skippedStops.count)", label: "Skipped")
                }
                let totalMin = stops.reduce(0) { $0 + $1.actualMinutes }
                if totalMin > 0 {
                    let h = totalMin / 60, m = totalMin % 60
                    let label = h > 0 ? "\(h)h \(m)m" : "\(m)m"
                    statCell(value: label, label: "On Route")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
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
