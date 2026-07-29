import SwiftUI
import SwiftData

struct EditRouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]

    let route: PlowRoute
    private let originalStopIDs: Set<UUID>

    @State private var routeName: String
    @State private var stops: [RouteStop]
    @State private var showingClientPicker = false

    init(route: PlowRoute) {
        self.route = route
        self.originalStopIDs = Set((route.stops ?? []).map { $0.id })
        _routeName = State(initialValue: route.name)
        _stops = State(initialValue: route.sortedStops)
    }

    var availableClients: [Client] {
        allClients
            .filter { $0.operatorID == authManager.userID }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route Name") {
                    TextField("Route name", text: $routeName)
                }

                Section {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.clientName)
                                    .font(.headline)
                                if !stop.clientAddress.isEmpty {
                                    Text(stop.clientAddress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onMove { from, to in
                        stops.move(fromOffsets: from, toOffset: to)
                        for index in stops.indices { stops[index].order = index }
                    }
                    .onDelete { offsets in
                        stops.remove(atOffsets: offsets)
                    }

                    Button {
                        showingClientPicker = true
                    } label: {
                        Label("Add Stop", systemImage: "plus")
                    }
                } header: {
                    Text("Stops")
                } footer: {
                    if stops.count > 1 { Text("Drag to reorder stops.") }
                }
            }
            .navigationTitle("Edit Route")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .disabled(routeName.isEmpty || stops.isEmpty)
                }
            }
            .sheet(isPresented: $showingClientPicker) {
                ClientPickerView(
                    clients: availableClients,
                    alreadyAdded: stops.map { $0.clientID },
                    onSelect: { client in
                        let stop = RouteStop(order: stops.count, client: client)
                        stops.append(stop)
                    },
                    onCustomStop: { name, address, phone in
                        let stop = RouteStop(order: stops.count, customName: name, customAddress: address, customPhone: phone)
                        stops.append(stop)
                    }
                )
            }
        }
    }

    private func saveChanges() {
        route.name = routeName

        let currentStopIDs = Set(stops.map { $0.id })

        // Delete stops that were removed
        for stop in (route.stops ?? []) where !currentStopIDs.contains(stop.id) {
            modelContext.delete(stop)
        }

        // Update order and insert any newly added stops
        for (index, stop) in stops.enumerated() {
            stop.order = index
            if !originalStopIDs.contains(stop.id) {
                modelContext.insert(stop)
            }
        }

        route.stops = stops
        dismiss()
    }
}
