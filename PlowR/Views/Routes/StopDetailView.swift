import SwiftUI
import SwiftData
import MessageUI

/// A stop on a route, before the route runs: what it's expected to need, the
/// notes and equipment shown while the route runs, its target time, and ways
/// to reach the client. A route's stops used to be view-only; none of this
/// could be set from the route. (No link to edit the client from here: making
/// them inactive there would delete this very stop.)
struct StopDetailView: View {
    let stop: RouteStop
    let client: Client?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var allServices: [ServiceItem]

    @State private var selectedIDs: Set<String>
    @State private var stopNotes: String
    @State private var equipmentNotes: String
    @State private var targetMinutes: Int
    @State private var askingWhereServicesApply = false
    @State private var showingDiscardConfirm = false
    @State private var showingMessage = false

    private let openedServices: Set<String>

    init(stop: RouteStop, client: Client?) {
        self.stop = stop
        self.client = client
        let expected = Set(StopServices.expected(for: stop, client: client))
        _selectedIDs = State(initialValue: expected)
        openedServices = expected
        _stopNotes = State(initialValue: stop.stopNotes)
        _equipmentNotes = State(initialValue: stop.equipmentNotes)
        _targetMinutes = State(initialValue: stop.targetMinutes)
    }

    private var operatorID: String { client?.operatorID ?? stop.route?.operatorID ?? "" }
    private var services: [StopRecording.Service] { ServiceLog.activeServices(allServices, operatorID: operatorID) }
    private var servicesChanged: Bool { selectedIDs != openedServices }
    private var hasChanges: Bool {
        servicesChanged || stopNotes != stop.stopNotes || equipmentNotes != stop.equipmentNotes
            || targetMinutes != stop.targetMinutes
    }

    /// What the stop's time falls back to (RouteFacts.targetMinutes): its
    /// place's goal, the client's own or their property's.
    private var placeGoalLabel: String {
        guard let client, let place = Place.of(client, propertyID: stop.propertyID), place.goalMinutes > 0
        else { return "None" }
        return place.isMain ? "Client's goal" : "Property's goal"
    }

    // PlowR Pro: read only, this editor shows why instead (EditsNeedPro).
    var body: some View { editor.editsNeedPro() }

    @ViewBuilder private var editor: some View {
        // Deleted while open (another device, or its client made inactive):
        // the page is on its way out and mustn't read the stop.
        if stop.isDeleted || stop.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            page
        }
    }

    private var page: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.clientName).font(.headline)
                        if !stop.clientAddress.isEmpty {
                            Text(stop.clientAddress).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    contactRow
                }

                Section {
                    if services.isEmpty {
                        StandardServicesOffer(operatorID: operatorID)
                    } else {
                        ForEach(services, id: \.id) { service in
                            Toggle(service.name, isOn: Binding(
                                get: { selectedIDs.contains(service.id) },
                                set: { on in
                                    if on { selectedIDs.insert(service.id) } else { selectedIDs.remove(service.id) }
                                }))
                        }
                    }
                } header: {
                    Text("Expected Services")
                } footer: {
                    Text(servicesFooter)
                }

                Section {
                    TextField("Shown at this stop during the route", text: $stopNotes, axis: .vertical)
                        .lineLimit(2...)
                } header: {
                    Label("Stop Notes", systemImage: "note.text")
                }

                Section {
                    TextField("Equipment or tools to bring", text: $equipmentNotes, axis: .vertical)
                        .lineLimit(2...)
                } header: {
                    Label("Equipment", systemImage: "wrench.and.screwdriver")
                }

                Section {
                    Stepper(value: $targetMinutes, in: 0...480, step: 5) {
                        LabeledContent("Target Time", value: targetMinutes > 0 ? RouteFacts.duration(targetMinutes)
                                       : placeGoalLabel)
                    }
                } footer: {
                    // The client's average is over all their places: said only at their own address.
                    if let client, client.averageServiceMinutes > 0, Place.isMain(stop.propertyID, of: client) {
                        Text("Usually about \(RouteFacts.duration(Int(client.averageServiceMinutes.rounded()))) here.")
                    }
                }
            }
            .navigationTitle("Stop")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { showingDiscardConfirm = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Services changed on a client's stop: ask where it applies.
                        if servicesChanged, client != nil { askingWhereServicesApply = true } else { save(allRoutes: false) }
                    }
                    .disabled(!hasChanges)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Change the expected services…", isPresented: $askingWhereServicesApply,
                                titleVisibility: .visible) {
                Button("Only on This Route") { save(allRoutes: false) }
                Button("On All Routes From Now On") { save(allRoutes: true) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("On all routes makes these \(stop.clientName)'s usual services, and every route's stop for them expects them, replacing any set for one route.")
            }
            .confirmationDialog("Discard your changes?", isPresented: $showingDiscardConfirm, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
            .sheet(isPresented: $showingMessage) {
                MessageComposer(recipients: [stop.clientPhone], body: "") { outcome in
                    if outcome == .sent { TextLog.record(.text, body: "", to: [stop.clientID], in: modelContext) }
                }
            }
        }
    }

    private var servicesFooter: String {
        if stop.isCustomStop { return "For this stop on this route." }
        if stop.hasOwnServices { return "Set for this stop on this route." }
        return "\(stop.clientName)'s usual services. Changing them asks whether it's for this route only."
    }

    @ViewBuilder
    private var contactRow: some View {
        let digits = stop.clientPhone.filter(\.isNumber)
        HStack(spacing: 8) {
            if !digits.isEmpty {
                contactButton("Call", systemImage: "phone.fill") {
                    if let url = URL(string: "tel:\(digits)") { openURL(url) }
                }
                if MFMessageComposeViewController.canSendText() {
                    contactButton("Text", systemImage: "message.fill") { showingMessage = true }
                }
            }
            if let url = stop.appleMapsDirectionsURL {
                contactButton("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") { openURL(url) }
            }
        }
    }

    private func contactButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func save(allRoutes: Bool) {
        let ids = services.map(\.id).filter { selectedIDs.contains($0) }
            + selectedIDs.filter { id in !services.contains { $0.id == id } }.sorted()
        StopServices.apply(ids, to: stop, client: client, allRoutes: allRoutes, openedWith: openedServices,
                           in: modelContext)
        stop.stopNotes = stopNotes
        stop.equipmentNotes = equipmentNotes
        stop.targetMinutes = targetMinutes
        try? modelContext.save()
        dismiss()
    }
}
