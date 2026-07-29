import SwiftUI
import SwiftData

struct CreateRouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]

    @State private var routeName = ""
    @State private var selectedStops: [RouteStop] = []
    @State private var showingClientPicker = false

    var availableClients: [Client] {
        allClients
            .filter { $0.operatorID == authManager.userID }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route Name") {
                    TextField("e.g. Monday North Side", text: $routeName)
                }

                Section {
                    ForEach(Array(selectedStops.enumerated()), id: \.element.id) { index, stop in
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
                        selectedStops.move(fromOffsets: from, toOffset: to)
                        for index in selectedStops.indices {
                            selectedStops[index].order = index
                        }
                    }
                    .onDelete { offsets in
                        selectedStops.remove(atOffsets: offsets)
                    }

                    Button {
                        showingClientPicker = true
                    } label: {
                        Label("Add Stop", systemImage: "plus")
                    }
                } header: {
                    Text("Stops")
                } footer: {
                    if selectedStops.count > 1 {
                        Text("Drag to reorder stops.")
                    }
                }
            }
            .navigationTitle("New Route")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRoute() }
                        .disabled(routeName.isEmpty || selectedStops.isEmpty)
                }
            }
            .sheet(isPresented: $showingClientPicker) {
                ClientPickerView(
                    clients: availableClients,
                    alreadyAdded: selectedStops.map { $0.clientID },
                    onSelect: { client in
                        let stop = RouteStop(order: selectedStops.count, client: client)
                        if client.goalMinutes > 0 { stop.targetMinutes = client.goalMinutes }
                        selectedStops.append(stop)
                    },
                    onCustomStop: { name, address, phone in
                        let stop = RouteStop(order: selectedStops.count, customName: name, customAddress: address, customPhone: phone)
                        selectedStops.append(stop)
                    }
                )
            }
        }
    }

    // MARK: - Save

    private func saveRoute() {
        let route = PlowRoute(name: routeName, operatorID: authManager.userID)
        for index in selectedStops.indices {
            selectedStops[index].order = index
        }
        route.stops = selectedStops
        modelContext.insert(route)
        dismiss()
    }
}

#Preview {
    CreateRouteView()
        .environment(AuthManager())
        .modelContainer(for: [PlowRoute.self, RouteStop.self, Client.self], inMemory: true)
}
