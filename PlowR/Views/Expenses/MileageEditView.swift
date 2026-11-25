import SwiftUI
import SwiftData

/// Logs or changes a trip in the mileage log (Home → Expenses → Mileage).
/// The distance is typed: PlowR doesn't measure it.
struct MileageEditView: View {
    /// nil: a new trip.
    let editing: MileageEntry?
    let operatorID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allClients: [Client]
    @Query private var allRoutes: [PlowRoute]

    @State private var date: Date
    @State private var distanceText: String
    /// A trip keeps the unit it was typed in; a new one takes the region's.
    private let unit: DistanceUnit
    @State private var purpose: String
    @State private var clientID: String
    @State private var clientName: String
    @State private var routeID: String
    @State private var routeName: String
    @State private var note: String
    @State private var showingDiscardConfirm = false
    @State private var showingDeleteConfirm = false

    init(editing: MileageEntry? = nil, operatorID: String) {
        self.editing = editing
        self.operatorID = operatorID
        unit = editing?.unit ?? DistanceUnit.default(for: .current)
        _date = State(initialValue: editing?.date ?? Date())
        _distanceText = State(initialValue: editing.map { DecimalText.trimmed($0.distance, places: 2) } ?? "")
        _purpose = State(initialValue: editing?.purpose ?? "")
        _clientID = State(initialValue: editing?.clientID ?? "")
        _clientName = State(initialValue: editing?.clientName ?? "")
        _routeID = State(initialValue: editing?.routeID ?? "")
        _routeName = State(initialValue: editing?.routeName ?? "")
        _note = State(initialValue: editing?.note ?? "")
    }

    private var distance: Double? { Mileage.distance(typed: distanceText) }
    private var trimmedPurpose: String { purpose.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { distance != nil && !trimmedPurpose.isEmpty }

    private var hasChanges: Bool {
        guard let editing else {
            return !distanceText.isEmpty || !purpose.isEmpty || !note.isEmpty || !clientID.isEmpty || !routeID.isEmpty
        }
        return date != editing.date || distance != editing.distance || purpose != editing.purpose
            || clientID != editing.clientID || routeID != editing.routeID || note != editing.note
    }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == operatorID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var myRoutes: [PlowRoute] {
        allRoutes.filter { $0.operatorID == operatorID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // PlowR Pro: read only, this editor shows why instead (EditsNeedPro).
    var body: some View { editor.editsNeedPro() }

    private var editor: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    LabeledContent("Distance") {
                        HStack(spacing: PlowRLayout.space1) {
                            TextField("0", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text(unit.rawValue).foregroundStyle(PlowRColor.inkSecondary)
                        }
                    }
                    if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty, distance == nil {
                        Label("Enter a distance above zero, such as 12.5.", systemImage: PlowRSymbol.warning.name)
                            .foregroundStyle(PlowRColor.Status.overdue.text)
                    }
                    TextField("Purpose, such as Supply run", text: $purpose)
                        .textInputAutocapitalization(.sentences)
                } footer: {
                    SectionNote("Type the distance from your odometer or a map. PlowR doesn't track mileage by GPS.")
                }
                .listRowBackground(PlowRColor.surface)

                Section(title: "For") {
                    ExpenseLinkFields(clients: myClients, routes: myRoutes, clientID: $clientID,
                                      clientName: $clientName, routeID: $routeID, routeName: $routeName)
                }
                .listRowBackground(PlowRColor.surface)

                Section(title: "Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(2...)
                }
                .listRowBackground(PlowRColor.surface)

                if editing != nil {
                    Section {
                        Button("Delete Trip", role: .destructive) { showingDeleteConfirm = true }
                    }
                    .listRowBackground(PlowRColor.surface)
                }
            }
            .plowRGrouped()
            .navigationTitle(editing == nil ? "Log Mileage" : "Trip")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { showingDiscardConfirm = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard changes?", isPresented: $showingDiscardConfirm, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
            .confirmationDialog(editing.map { Mileage.deleteTitle(for: $0) } ?? "",
                                isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Trip", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func save() {
        guard let distance, canSave else { return }
        let entry = editing ?? {
            let new = MileageEntry(operatorID: operatorID, unit: unit)
            modelContext.insert(new)
            return new
        }()
        entry.date = date
        entry.distance = distance
        entry.purpose = trimmedPurpose
        entry.clientID = clientID
        entry.clientName = clientName
        entry.routeID = routeID
        entry.routeName = routeName
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    private func delete() {
        guard let editing else { return }
        modelContext.delete(editing)
        try? modelContext.save()
        dismiss()
    }
}
