import SwiftUI
import SwiftData

struct AddVisitView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allClients: [Client]
    @Query private var allServiceItems: [ServiceItem]
    @Query private var allProfiles: [BusinessProfile]

    /// Offered whatever the work, after the business's own services.
    static let generalReasons = ["Inspection", "Routine Visit"]

    /// The picker's own entry for a reason typed in: never a listed reason
    /// too, or picking it would save an empty reason.
    static let otherReason = "Other"

    /// This business's active services in catalog order: the reasons, and
    /// the Expected Services list.
    static func activeServices(_ services: [ServiceItem], operatorID: String) -> [ServiceItem] {
        services.filter { $0.operatorID == operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The reasons to offer: this business's active services, then the
    /// general ones, then its own saved reasons. The list used to be four
    /// snow services and two general ones, whatever the business did.
    static func reasonPresets(services: [ServiceItem], operatorID: String, saved: [String]) -> [String] {
        let mine = activeServices(services, operatorID: operatorID).map(\.name)
        var listed: Set<String> = [otherReason, ""]
        return (mine + generalReasons + saved).filter { listed.insert($0).inserted }
    }

    /// Whether a typed reason can be saved as a preset: not empty, not listed
    /// already, and not "Other", which is the picker's own entry and would
    /// leave the visit with no reason.
    static func canSaveAsPreset(_ reason: String, presets: [String]) -> Bool {
        !reason.isEmpty && reason != otherReason && !presets.contains(reason)
    }

    /// How a visit's saved reason shows in the picker: as a listed reason,
    /// or as Other with its text (a service since removed, a typed reason).
    static func pickerSelection(for reason: String, presets: [String]) -> (preset: String, custom: String) {
        if reason.isEmpty { return ("", "") }
        return presets.contains(reason) ? (reason, "") : (otherReason, reason)
    }

    // MARK: - Mode
    var editing: ScheduledVisit?

    // MARK: - Form State
    @State private var selectedClient: Client?
    @State private var scheduledDate: Date
    @State private var estimatedMinutes: Int
    @State private var notes: String
    @State private var isRecurring: Bool
    @State private var recurrenceType: RecurrenceType
    @State private var recurrenceInterval: Int
    @State private var hasEndDate: Bool
    @State private var recurrenceEndDate: Date
    @State private var recurrenceWeekdays: Set<Int>
    @State private var isAfterHours: Bool
    @State private var afterHoursMultiplier: Double
    @State private var selectedReasonPreset: String
    @State private var customReason: String
    @State private var selectedServiceIDs: Set<String>
    @State private var showingAddClientSheet = false
    @State private var showingRecurringEditDialog = false

    // Create new visit
    init(initialDate: Date = Date()) {
        self.editing = nil
        _scheduledDate = State(initialValue: initialDate)
        _estimatedMinutes = State(initialValue: 0)
        _notes = State(initialValue: "")
        _isRecurring = State(initialValue: false)
        _recurrenceType = State(initialValue: .weekly)
        _recurrenceInterval = State(initialValue: 1)
        _hasEndDate = State(initialValue: false)
        _recurrenceEndDate = State(initialValue: Date().addingTimeInterval(86400 * 90))
        _recurrenceWeekdays = State(initialValue: [])
        _selectedClient = State(initialValue: nil)
        _isAfterHours = State(initialValue: false)
        _afterHoursMultiplier = State(initialValue: 1.5)
        _selectedReasonPreset = State(initialValue: "")
        _customReason = State(initialValue: "")
        _selectedServiceIDs = State(initialValue: [])
    }

    // Create new visit pre-filled for a specific client
    init(client: Client, initialDate: Date = Date()) {
        self.editing = nil
        _scheduledDate = State(initialValue: initialDate)
        _estimatedMinutes = State(initialValue: client.goalMinutes)
        _notes = State(initialValue: client.defaultStopNotes)
        _isRecurring = State(initialValue: false)
        _recurrenceType = State(initialValue: .weekly)
        _recurrenceInterval = State(initialValue: 1)
        _hasEndDate = State(initialValue: false)
        _recurrenceEndDate = State(initialValue: Date().addingTimeInterval(86400 * 90))
        _recurrenceWeekdays = State(initialValue: [])
        _selectedClient = State(initialValue: client)
        _isAfterHours = State(initialValue: false)
        _afterHoursMultiplier = State(initialValue: 1.5)
        _selectedReasonPreset = State(initialValue: "")
        _customReason = State(initialValue: "")
        _selectedServiceIDs = State(initialValue: [])
    }

    // Edit existing visit
    init(editing: ScheduledVisit) {
        self.editing = editing
        _scheduledDate = State(initialValue: editing.scheduledDate)
        _estimatedMinutes = State(initialValue: editing.estimatedMinutes)
        _notes = State(initialValue: editing.notes)
        _isRecurring = State(initialValue: editing.isRecurring)
        _recurrenceType = State(initialValue: editing.recurrenceType)
        _recurrenceInterval = State(initialValue: editing.recurrenceInterval)
        _hasEndDate = State(initialValue: editing.recurrenceEndDate != nil)
        _recurrenceEndDate = State(initialValue: editing.recurrenceEndDate ?? Date().addingTimeInterval(86400 * 90))
        _recurrenceWeekdays = State(initialValue: Set(editing.recurrenceWeekdays))
        _selectedClient = State(initialValue: nil) // resolved in onAppear
        _isAfterHours = State(initialValue: editing.isAfterHours)
        _afterHoursMultiplier = State(initialValue: editing.afterHoursMultiplier)
        // Reason: as typed in until onAppear, when the catalog it may come from can be read.
        let selection = AddVisitView.pickerSelection(for: editing.visitReason, presets: [])
        _selectedReasonPreset = State(initialValue: selection.preset)
        _customReason = State(initialValue: selection.custom)
        _selectedServiceIDs = State(initialValue: Set(editing.expectedServiceIDs))
    }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }
            .sorted { $0.name < $1.name }
    }

    private var myServices: [ServiceItem] {
        Self.activeServices(allServiceItems, operatorID: authManager.userID)
    }

    private var operatorProfile: BusinessProfile? {
        allProfiles.first { $0.operatorID == authManager.userID }
    }

    private var allReasonPresets: [String] {
        Self.reasonPresets(services: allServiceItems, operatorID: authManager.userID,
                           saved: operatorProfile?.customVisitReasons ?? [])
    }

    private var resolvedReason: String {
        selectedReasonPreset == Self.otherReason ? customReason : selectedReasonPreset
    }

    private func saveReasonAsPreset() {
        guard let profile = operatorProfile,
              Self.canSaveAsPreset(customReason, presets: allReasonPresets) else { return }
        profile.customVisitReasons.append(customReason)
        selectedReasonPreset = customReason
        customReason = ""
    }

    private var isValid: Bool { selectedClient != nil }

    private var intervalLabel: String {
        switch recurrenceType {
        case .daily:    return "Every \(recurrenceInterval) day\(recurrenceInterval == 1 ? "" : "s")"
        case .weekly:   return "Every \(recurrenceInterval) week\(recurrenceInterval == 1 ? "" : "s")"
        case .monthly:  return "Every \(recurrenceInterval) month\(recurrenceInterval == 1 ? "" : "s")"
        case .biweekly: return "Every 2 weeks"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                clientSection
                dateSection
                visitInfoSection
                detailsSection
                if editing == nil { recurrenceSection }
            }
            .navigationTitle(editing == nil ? "Add Visit" : "Edit Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") {
                        if editing?.isRecurring == true && !(editing?.seriesID.isEmpty ?? true) {
                            showingRecurringEditDialog = true
                        } else {
                            save()
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let e = editing {
                selectedClient = myClients.first { $0.id.uuidString == e.clientID }
                (selectedReasonPreset, customReason) = Self.pickerSelection(for: e.visitReason,
                                                                            presets: allReasonPresets)
            }
        }
        .sheet(isPresented: $showingAddClientSheet) {
            AddClientView()
        }
        .confirmationDialog(
            "Edit Recurring Visit",
            isPresented: $showingRecurringEditDialog,
            titleVisibility: .visible
        ) {
            Button("This Visit Only") {
                saveThisOnly()
                dismiss()
            }
            Button("This & All Future Visits") {
                saveAllFuture()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("How would you like to apply your changes?")
        }
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section("Client") {
            if myClients.isEmpty {
                Text("No clients yet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Client", selection: $selectedClient) {
                    Text("Select a client").tag(Optional<Client>.none)
                    ForEach(myClients) { client in
                        VStack(alignment: .leading) {
                            Text(client.name)
                            if !client.address.isEmpty {
                                Text(client.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(client))
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Button {
                showingAddClientSheet = true
            } label: {
                Label("New Client", systemImage: "person.badge.plus")
                    .font(.subheadline)
            }
        }
    }

    private var dateSection: some View {
        Section("Date & Time") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    timeButton("6 AM",  hour: 6)
                    timeButton("7 AM",  hour: 7)
                    timeButton("8 AM",  hour: 8)
                    timeButton("9 AM",  hour: 9)
                    timeButton("12 PM", hour: 12)
                    timeButton("2 PM",  hour: 14)
                    timeButton("4 PM",  hour: 16)
                    timeButton("6 PM",  hour: 18)
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))

            DatePicker("Date", selection: $scheduledDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
        }
    }

    private func timeButton(_ label: String, hour: Int) -> some View {
        let isSelected = Calendar.current.component(.hour, from: scheduledDate) == hour
        return Button(label) {
            scheduledDate = Calendar.current.date(
                bySettingHour: hour, minute: 0, second: 0, of: scheduledDate
            ) ?? scheduledDate
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isSelected ? .blue : nil)
    }

    private var visitInfoSection: some View {
        Section("Visit Info") {
            Picker("Reason", selection: $selectedReasonPreset) {
                Text("None").tag("")
                ForEach(allReasonPresets, id: \.self) { preset in
                    Text(preset).tag(preset)
                }
                Text("Other…").tag(Self.otherReason)
            }
            if selectedReasonPreset == Self.otherReason {
                TextField("Describe the visit reason…", text: $customReason)
                if Self.canSaveAsPreset(customReason, presets: allReasonPresets),
                   operatorProfile != nil {
                    Button {
                        saveReasonAsPreset()
                    } label: {
                        Label("Save as Preset", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                }
            }
            if !myServices.isEmpty {
                NavigationLink {
                    servicePickerView
                } label: {
                    HStack {
                        Text("Expected Services")
                        Spacer()
                        if selectedServiceIDs.isEmpty {
                            Text("None")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(selectedServiceIDs.count) selected")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var servicePickerView: some View {
        List {
            ForEach(myServices) { service in
                let isSelected = selectedServiceIDs.contains(service.id.uuidString)
                Button {
                    if isSelected {
                        selectedServiceIDs.remove(service.id.uuidString)
                    } else {
                        selectedServiceIDs.insert(service.id.uuidString)
                    }
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name)
                                .foregroundStyle(.primary)
                            Text(service.category.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Expected Services")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailsSection: some View {
        Section("Details") {
            HStack {
                Text("Est. Duration")
                Spacer()
                Picker("Minutes", selection: $estimatedMinutes) {
                    Text("Not set").tag(0)
                    ForEach([15, 30, 45, 60, 90, 120, 150, 180], id: \.self) { m in
                        Text(m < 60 ? "\(m) min" : (m % 60 == 0 ? "\(m/60) hr" : "\(m/60) hr \(m%60) min"))
                            .tag(m)
                    }
                }
                .pickerStyle(.menu)
            }
            Toggle("After Hours", isOn: $isAfterHours.animation())
            if isAfterHours {
                HStack {
                    Text("Cost Multiplier")
                    Spacer()
                    Picker("", selection: $afterHoursMultiplier) {
                        Text("1.25×").tag(1.25)
                        Text("1.5×").tag(1.5)
                        Text("1.75×").tag(1.75)
                        Text("2×").tag(2.0)
                    }
                    .pickerStyle(.menu)
                }
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(3)
        }
    }

    private var recurrenceSection: some View {
        Section("Recurrence") {
            Toggle("Repeat", isOn: $isRecurring.animation())

            if isRecurring {
                Picker("Frequency", selection: $recurrenceType) {
                    ForEach(RecurrenceType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                if recurrenceType == .weekly {
                    weekdayPicker
                }

                if recurrenceType != .biweekly {
                    Stepper(intervalLabel, value: $recurrenceInterval, in: 1...30)
                }

                Toggle("End Date", isOn: $hasEndDate.animation())
                if hasEndDate {
                    DatePicker("Ends", selection: $recurrenceEndDate, in: scheduledDate..., displayedComponents: .date)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            ForEach(0..<7) { offset in
                let weekday = offset + 1
                let label = ["S","M","T","W","T","F","S"][offset]
                let selected = recurrenceWeekdays.contains(weekday)
                Button {
                    if selected { recurrenceWeekdays.remove(weekday) }
                    else { recurrenceWeekdays.insert(weekday) }
                } label: {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(selected ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(selected ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                if offset < 6 { Spacer() }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Save

    private func save() {
        guard let client = selectedClient else { return }
        if editing != nil { saveThisOnly(); return }


        let seriesID = UUID().uuidString
        client.isActive = true

        func makeVisit(on date: Date) -> ScheduledVisit {
            let visit = ScheduledVisit(
                operatorID: authManager.userID,
                clientID: client.id.uuidString,
                clientName: client.name,
                clientAddress: client.address,
                scheduledDate: date
            )
            visit.estimatedMinutes = estimatedMinutes
            visit.notes = notes
            visit.visitReason = resolvedReason
            visit.expectedServiceIDs = Array(selectedServiceIDs)
            visit.isRecurring = isRecurring
            visit.recurrenceType = recurrenceType
            visit.recurrenceInterval = recurrenceInterval
            visit.recurrenceWeekdays = recurrenceType == .weekly ? Array(recurrenceWeekdays).sorted() : []
            visit.recurrenceEndDate = hasEndDate ? recurrenceEndDate : nil
            visit.seriesID = seriesID
            visit.isAfterHours = isAfterHours
            visit.afterHoursMultiplier = afterHoursMultiplier
            return visit
        }

        // The series' dates come from the first visit's own rule: the same one
        // that continues the series when a visit is completed.
        let first = makeVisit(on: scheduledDate)
        var dates = [scheduledDate]
        if first.isRecurring {
            let horizon = Calendar.current.date(byAdding: RecurrenceRule.upFrontHorizon, to: scheduledDate)
            dates = first.recurrenceRule.occurrences(from: scheduledDate, horizon: horizon, calendar: .current)
        }

        for (index, date) in dates.enumerated() {
            let visit = index == 0 ? first : makeVisit(on: date)
            modelContext.insert(visit)
            let capturedVisit = visit
            Task {
                if let eventID = await CalendarService.shared.addVisit(capturedVisit) {
                    capturedVisit.externalCalendarID = eventID
                }
            }
        }
    }

    private func saveThisOnly() {
        guard let client = selectedClient, let existing = editing else { return }
        existing.clientID = client.id.uuidString
        existing.clientName = client.name
        existing.clientAddress = client.address
        existing.scheduledDate = scheduledDate
        existing.estimatedMinutes = estimatedMinutes
        existing.notes = notes
        existing.visitReason = resolvedReason
        existing.expectedServiceIDs = Array(selectedServiceIDs)
        existing.isAfterHours = isAfterHours
        existing.afterHoursMultiplier = afterHoursMultiplier
    }

    private func saveAllFuture() {
        guard let client = selectedClient, let existing = editing else { return }
        let cal = Calendar.current
        let newHour = cal.component(.hour, from: scheduledDate)
        let newMinute = cal.component(.minute, from: scheduledDate)
        let cutoff = existing.scheduledDate
        let sid = existing.seriesID

        let descriptor = FetchDescriptor<ScheduledVisit>(
            predicate: #Predicate<ScheduledVisit> { $0.seriesID == sid }
        )
        guard let seriesVisits = try? modelContext.fetch(descriptor) else {
            saveThisOnly()
            return
        }

        for visit in seriesVisits where visit.scheduledDate >= cutoff {
            visit.clientID = client.id.uuidString
            visit.clientName = client.name
            visit.clientAddress = client.address
            if visit.id == existing.id {
                visit.scheduledDate = scheduledDate
            } else if let newDate = cal.date(bySettingHour: newHour, minute: newMinute, second: 0, of: visit.scheduledDate) {
                visit.scheduledDate = newDate
            }
            visit.estimatedMinutes = estimatedMinutes
            visit.notes = notes
            visit.visitReason = resolvedReason
            visit.expectedServiceIDs = Array(selectedServiceIDs)
            visit.isAfterHours = isAfterHours
            visit.afterHoursMultiplier = afterHoursMultiplier
        }
    }
}
