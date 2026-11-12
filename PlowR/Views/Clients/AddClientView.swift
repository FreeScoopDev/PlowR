import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct AddClientView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

    @State private var draft: NewClientDraft
    @State private var asking = false
    @State private var geocodedCoordinate: CLLocationCoordinate2D? = nil
    @State private var isSaving = false
    @State private var addressCompleter = AddressCompleter()
    @State private var showingContactPicker = false
    /// Built, waiting for an answer: its address couldn't be put on the map.
    @State private var unplacedClient: Client?
    @State private var lookupProblem: AddressPin.Problem?

    /// `kind` is what the form opens on; the user can still change it.
    init(kind: NewClientDraft.Kind = .existingCustomer) {
        _draft = State(initialValue: NewClientDraft(kind: kind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(title: "Client Type") {
                    Picker("Client Type", selection: $draft.kind) {
                        ForEach(NewClientDraft.Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(PlowRColor.surface)

                Section(title: "Client Info") {
                    TextField("Full Name", text: $draft.name)
                        .textContentType(.name)
                    TextField("Phone Number (optional)", text: $draft.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email (optional)", text: $draft.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                .listRowBackground(PlowRColor.surface)

                Section(title: "Service Address") {
                    TextField("Street Address", text: $draft.address)
                        .textContentType(.fullStreetAddress)
                        .onChange(of: draft.address) { _, v in
                            if addressCompleter.fieldChanged(to: v) { geocodedCoordinate = nil }
                        }

                    if !addressCompleter.completions.isEmpty {
                        ForEach(addressCompleter.completions, id: \.self) { completion in
                            Button {
                                Task {
                                    let result = await addressCompleter.resolve(completion)
                                    draft.address = result.address
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
                                            .foregroundStyle(PlowRColor.inkSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(PlowRColor.surface)

                Section {
                    TextField("Gate code, dog in the yard…", text: $draft.routeNotes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    SectionTitle("Route Notes")
                } footer: {
                    SectionNote("Shown at this client's stops on a route.")
                }
                .listRowBackground(PlowRColor.surface)
            }
            .plowRGrouped()
            .navigationTitle("New Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if draft.hasTypedWork { asking = true } else { dismiss() }
                    }
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
                            .disabled(!draft.canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving || draft.hasTypedWork)
            .confirmationDialog("Discard this client?", isPresented: $asking, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("What you typed hasn't been saved.")
            }
            .addressLookupAlert($lookupProblem) {
                if let client = unplacedClient { modelContext.insert(client) }
                unplacedClient = nil
                dismiss()
            } tryAgain: {
                if let client = unplacedClient { place(client) }
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPickerView { importedName, importedPhone, importedEmail, importedAddress in
                    draft.name = importedName
                    draft.phone = importedPhone
                    draft.email = importedEmail
                    draft.address = importedAddress
                    showingContactPicker = false
                } onCancel: {
                    showingContactPicker = false
                }
            }
        }
    }

    private func saveClient() {
        isSaving = true
        let client = draft.makeClient(operatorID: authManager.userID, now: .now)

        if let coord = geocodedCoordinate {
            client.latitude = coord.latitude
            client.longitude = coord.longitude
            modelContext.insert(client)
            isSaving = false
            dismiss()
            return
        }

        guard !client.address.isEmpty else {
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
