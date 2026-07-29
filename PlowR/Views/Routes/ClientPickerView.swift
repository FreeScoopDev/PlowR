import SwiftUI

struct ClientPickerView: View {
    let clients: [Client]
    let alreadyAdded: [UUID]
    let onSelect: (Client) -> Void
    let onCustomStop: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCustomForm = false
    @State private var localAdded: Set<UUID>

    init(clients: [Client], alreadyAdded: [UUID],
         onSelect: @escaping (Client) -> Void,
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
                            let isAdded = localAdded.contains(client.id)
                            Button {
                                guard !isAdded else { return }
                                onSelect(client)
                                localAdded.insert(client.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(client.name)
                                            .font(.headline)
                                            .foregroundStyle(isAdded ? .secondary : .primary)
                                        if !client.address.isEmpty {
                                            Text(client.address)
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
