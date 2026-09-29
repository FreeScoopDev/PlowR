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
    @State private var email = ""
    @State private var address = ""
    @State private var geocodedCoordinate: CLLocationCoordinate2D? = nil
    @State private var isSaving = false
    @State private var addressCompleter = AddressCompleter()
    @State private var showingContactPicker = false
    /// Built, waiting for an answer: its address couldn't be put on the map.
    @State private var unplacedClient: Client?
    @State private var lookupProblem: AddressPin.Problem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Client Info") {
                    TextField("Full Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone Number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email (optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section("Service Address") {
                    TextField("Street Address", text: $address)
                        .textContentType(.fullStreetAddress)
                        .onChange(of: address) { _, v in
                            if addressCompleter.fieldChanged(to: v) { geocodedCoordinate = nil }
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
            .interactiveDismissDisabled(isSaving)
            .addressLookupAlert($lookupProblem) {
                if let client = unplacedClient { modelContext.insert(client) }
                unplacedClient = nil
                dismiss()
            } tryAgain: {
                if let client = unplacedClient { place(client) }
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPickerView { importedName, importedPhone, importedEmail, importedAddress in
                    name = importedName
                    phone = importedPhone
                    email = importedEmail
                    address = importedAddress
                    showingContactPicker = false
                } onCancel: {
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
        client.email = email

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

        place(client)
    }

    /// Puts the new client on the map, then saves them; or asks what to do
    /// when their address can't be found or the map can't be reached. They
    /// used to be saved with no pin, and nothing said so.
    private func place(_ client: Client) {
        isSaving = true
        lookupProblem = nil
        Task {
            let problem = await AddressPin.place(client)
            isSaving = false
            if let problem {
                unplacedClient = client
                lookupProblem = problem
            } else {
                modelContext.insert(client)
                dismiss()
            }
        }
    }
}

#Preview {
    AddClientView()
        .environment(AuthManager())
        .modelContainer(for: Client.self, inMemory: true)
}
