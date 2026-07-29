import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct AddClientView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var geocodedCoordinate: CLLocationCoordinate2D? = nil
    @State private var isSaving = false
    @State private var addressCompleter = AddressCompleter()
    @State private var showingContactPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Client Info") {
                    TextField("Full Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone Number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                Section("Service Address") {
                    TextField("Street Address", text: $address)
                        .textContentType(.fullStreetAddress)
                        .onChange(of: address) { _, v in
                            geocodedCoordinate = nil
                            addressCompleter.search(v)
                        }

                    if !addressCompleter.completions.isEmpty {
                        ForEach(addressCompleter.completions, id: \.self) { completion in
                            Button {
                                Task {
                                    let result = await addressCompleter.resolve(completion)
                                    address = result.address
                                    geocodedCoordinate = result.coordinate
                                    addressCompleter.clear()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .foregroundStyle(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingContactPicker = true
                    } label: {
                        Label("Import Contact", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { saveClient() }
                            .disabled(name.isEmpty || phone.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPickerView { importedName, importedPhone, importedAddress in
                    name = importedName
                    phone = importedPhone
                    address = importedAddress
                    showingContactPicker = false
                }
            }
        }
    }

    private func saveClient() {
        isSaving = true
        let client = Client(
            name: name,
            phone: phone,
            address: address,
            operatorID: authManager.userID
        )

        if let coord = geocodedCoordinate {
            client.latitude = coord.latitude
            client.longitude = coord.longitude
            modelContext.insert(client)
            isSaving = false
            dismiss()
            return
        }

        guard !address.isEmpty else {
            modelContext.insert(client)
            isSaving = false
            dismiss()
            return
        }

        Task {
            let geocoder = CLGeocoder()
            if let placemark = try? await geocoder.geocodeAddressString(address).first,
               let location = placemark.location {
                client.latitude = location.coordinate.latitude
                client.longitude = location.coordinate.longitude
            }
            modelContext.insert(client)
            await MainActor.run { isSaving = false; dismiss() }
        }
    }
}

#Preview {
    AddClientView()
        .environment(AuthManager())
        .modelContainer(for: Client.self, inMemory: true)
}
