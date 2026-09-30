import SwiftUI

/// Adding stops to a route: a client at their own address, or at one of
/// their other properties (a row for each place). A place already on the
/// route can't be added twice.
struct ClientPickerView: View {
    let clients: [Client]
    /// Places already on the route (Place.key).
    let alreadyAdded: [String]
    let onSelect: (Client, Place) -> Void
    let onCustomStop: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCustomForm = false
    @State private var localAdded: Set<String>

    init(clients: [Client], alreadyAdded: [String],
         onSelect: @escaping (Client, Place) -> Void,
         onCustomStop: @escaping (String, String, String) -> Void) {
        self.clients = clients
        self.alreadyAdded = alreadyAdded
        self.onSelect = onSelect
        self.onCustomStop = onCustomStop
        _localAdded = State(initialValue: Set(alreadyAdded))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingCustomForm = true
                    } label: {
                        Label("Enter Manually (One-Time Stop)", systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("For one-time customers or stops that aren't set up as clients.")
                }

                if !clients.isEmpty {
                    Section("Your Clients") {
                        ForEach(clients) { client in
                            ForEach(Place.all(of: client), id: \.id) { place in
                                row(client, place)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Stops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCustomForm) {
                CustomStopFormView { name, address, phone in
                    onCustomStop(name, address, phone)
                }
            }
        }
    }

    private func row(_ client: Client, _ place: Place) -> some View {
        let key = Place.key(clientID: client.id, propertyID: place.storedID)
        let isAdded = localAdded.contains(key)
        return Button {
            guard !isAdded else { return }
            onSelect(client, place)
            localAdded.insert(key)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.title(for: client.name))
                        .font(.headline)
                        .foregroundStyle(isAdded ? .secondary : .primary)
                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .disabled(isAdded)
    }
}

// MARK: - Custom Stop Form

struct CustomStopFormView: View {
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var phone = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Stop Details") {
                    TextField("Name or Description", text: $name)
                        .textContentType(.name)
                    TextField("Address (optional)", text: $address)
                        .textContentType(.fullStreetAddress)
                    TextField("Phone (optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                Section {
                    Text("Use this for gas stations, supply pickups, one-time customers, or any stop that isn't saved as a client.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Custom Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onSave(name, address, phone) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
