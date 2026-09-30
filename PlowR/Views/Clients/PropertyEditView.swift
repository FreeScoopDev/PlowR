import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// One of a client's additional properties (a rental, a second lot): add
/// it, change it, or remove it. Its address is put on the map as a client's
/// is, and asks the same way when it can't be (addressLookupAlert).
struct PropertyEditView: View {
    let client: Client
    /// Nil: a new property.
    let property: Property?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServiceItems: [ServiceItem]

    @State private var draft: PropertyEditing.Draft
    @State private var addressCompleter = AddressCompleter()
    /// A picked suggestion's pin, until the address is typed over.
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var lookupProblem: AddressPin.Problem?
    @State private var isSaving = false
    /// The address being put on the map: what's saved with the pin found,
    /// even if the field changed while it was looked up.
    @State private var lookedUpAddress = ""
    @State private var removal: (stops: Int, visits: Int)?
    /// The routes Save would take it off, while that's asked.
    @State private var leavingRoutes: [String] = []
    private let originalAddress: String

    init(client: Client, property: Property?) {
        self.client = client
        self.property = property
        let draft = property.map(PropertyEditing.Draft.init) ?? PropertyEditing.Draft()
        _draft = State(initialValue: draft)
        originalAddress = draft.address
    }

    private var services: [ServiceItem] {
        allServiceItems
            .filter { $0.operatorID == client.operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        if let property, property.isDeleted || property.modelContext == nil {
            // Removed on another device while open: nothing left to save.
            Color.clear.onAppear { dismiss() }
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Rental on Elm", text: $draft.label)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("How it shows on routes and the schedule, after \(client.name)'s name.")
                }
                addressSection
                Section {
                    TextField("Notes shown at this stop (gate codes, where to start…)", text: $draft.stopNotes,
                              axis: .vertical)
                        .lineLimit(3)
                    Stepper(value: $draft.goalMinutes, in: 0...180, step: 5) {
                        LabeledContent("Stop goal time", value: draft.goalMinutes > 0 ? "\(draft.goalMinutes) min" : "Not set")
                    }
                } header: {
                    Text("Route")
                } footer: {
                    Text("Copied to new route stops here, as a client's own are.")
                }
                if !services.isEmpty { servicesSection }
                Section {
                    Toggle("Active", isOn: $draft.isActive)
                } footer: {
                    Text("An inactive property comes off its routes and isn't offered for new stops and visits. Visits already booked there stay.")
                }
                if property != nil {
                    Section {
                        Button("Remove Property", role: .destructive) {
                            guard let property else { return }
                            removal = PropertyRemoval.footprint(of: property, in: modelContext)
                        }
                    }
                }
            }
            // While the address is looked up: nothing changes under it, and
            // Cancel can't close a sheet whose save then lands anyway.
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .navigationTitle(property == nil ? "New Property" : "Edit Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { confirmThenSave() }
                            .disabled(!draft.canSave)
                    }
                }
            }
            .addressLookupAlert($lookupProblem, saveWithoutPin: {
                commit(address: lookedUpAddress, latitude: 0, longitude: 0)
            }, tryAgain: {
                save()
            }, keepCurrentPin: draft.hasPin ? {
                commit(address: lookedUpAddress, latitude: draft.latitude, longitude: draft.longitude)
            } : nil)
            .confirmationDialog("Mark \(draft.label.isEmpty ? "This Property" : draft.label) Inactive?",
                                isPresented: Binding(get: { !leavingRoutes.isEmpty },
                                                     set: { if !$0 { leavingRoutes = [] } }),
                                titleVisibility: .visible) {
                Button("Save and Mark Inactive", role: .destructive) {
                    leavingRoutes = []
                    save()
                }
                Button("Cancel", role: .cancel) { leavingRoutes = [] }
            } message: {
                Text(PropertyEditing.deactivateMessage(routeNames: leavingRoutes))
            }
            .confirmationDialog("Remove this property?",
                                isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
                                titleVisibility: .visible, presenting: removal) { _ in
                Button("Remove Property", role: .destructive) {
                    guard let property else { return }
                    PropertyRemoval.remove(property, in: modelContext)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { footprint in
                Text(PropertyEditing.removalMessage(stops: footprint.stops, visits: footprint.visits))
            }
        }
    }

    private var addressSection: some View {
        Section("Address") {
            TextField("Street Address", text: $draft.address)
                .textContentType(.fullStreetAddress)
                .onChange(of: draft.address) { _, text in
                    guard text != originalAddress else {
                        pickedCoordinate = nil
                        addressCompleter.clear()
                        return
                    }
                    if addressCompleter.fieldChanged(to: text) { pickedCoordinate = nil }
                }
            ForEach(addressCompleter.completions, id: \.self) { completion in
                Button {
                    Task {
                        let result = await addressCompleter.resolve(completion)
                        draft.address = result.address
                        pickedCoordinate = result.coordinate
                        addressCompleter.clear()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completion.title).foregroundStyle(.primary)
                        if !completion.subtitle.isEmpty {
                            Text(completion.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var servicesSection: some View {
        Section {
            ForEach(services) { service in
                let id = service.id.uuidString
                let isSelected = draft.expectedServiceIDs.contains(id)
                Button {
                    if isSelected { draft.expectedServiceIDs.remove(id) } else { draft.expectedServiceIDs.insert(id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        Text(service.name).foregroundStyle(.primary)
                    }
                }
            }
        } header: {
            Text("Default Services")
        } footer: {
            Text("Services this property typically needs. Its route stops expect these, except a stop given its own services on its route.")
        }
    }

    /// Asks first when Save marks it inactive and it's on a route.
    private func confirmThenSave() {
        leavingRoutes = PropertyEditing.routesLeft(saving: draft, to: property, in: modelContext)
        if leavingRoutes.isEmpty { save() }
    }

    /// A new address is put on the map first: a picked suggestion's pin, or
    /// looked up. The same address keeps the pin it has.
    private func save() {
        guard draft.address != originalAddress || property == nil else {
            return commit(address: draft.address, latitude: draft.latitude, longitude: draft.longitude)
        }
        if let pickedCoordinate {
            return commit(address: draft.address, latitude: pickedCoordinate.latitude,
                          longitude: pickedCoordinate.longitude)
        }
        isSaving = true
        let typed = draft.address
        lookedUpAddress = typed
        Task {
            let lookup = await AddressPin.lookUp(typed)
            isSaving = false
            switch lookup {
            case let .found(latitude, longitude):
                commit(address: typed, latitude: latitude, longitude: longitude)
            case .failed(let problem):
                lookupProblem = problem
            }
        }
    }

    /// Saves the page with this address and pin, which go together.
    private func commit(address: String, latitude: Double, longitude: Double) {
        var saved = draft
        saved.address = address
        saved.latitude = latitude
        saved.longitude = longitude
        PropertyEditing.save(saved, to: property, of: client, in: modelContext)
        dismiss()
    }
}
