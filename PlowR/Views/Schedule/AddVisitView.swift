import SwiftUI
import SwiftData

struct AddVisitView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allClients: [Client]

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
    }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }
            .sorted { $0.name < $1.name }
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

    // MARK: - Recurrence Helpers

    private func nextRecurrenceDate(after date: Date) -> Date? {
        var components = DateComponents()
        switch recurrenceType {
        case .daily:    components.day = recurrenceInterval
        case .weekly:   components.weekOfYear = recurrenceInterval
        case .biweekly: components.weekOfYear = 2
        case .monthly:  components.month = recurrenceInterval
        }
        return Calendar.current.date(byAdding: components, to: date)
    }

    // MARK: - Save

    private func save() {
        guard let client = selectedClient else { return }
        if editing != nil { saveThisOnly(); return }


        let seriesID = UUID().uuidString
        var dates: [Date] = [scheduledDate]

        if isRecurring {
            var cursor = scheduledDate
            for _ in 0..<51 {
                guard let next = nextRecurrenceDate(after: cursor) else { break }
                if hasEndDate && next > recurrenceEndDate { break }
                dates.append(next)
                cursor = next
            }
        }

        for date in dates {
            let visit = ScheduledVisit(
                operatorID: authManager.userID,
                clientID: client.id.uuidString,
                clientName: client.name,
                clientAddress: client.address,
                scheduledDate: date
            )
            visit.estimatedMinutes = estimatedMinutes
            visit.notes = notes
            visit.isRecurring = isRecurring
            visit.recurrenceType = recurrenceType
            visit.recurrenceInterval = recurrenceInterval
            visit.recurrenceWeekdays = Array(recurrenceWeekdays)
            visit.recurrenceEndDate = hasEndDate ? recurrenceEndDate : nil
            visit.seriesID = seriesID
            visit.isAfterHours = isAfterHours
            visit.afterHoursMultiplier = afterHoursMultiplier
            modelContext.insert(visit)
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
            visit.isAfterHours = isAfterHours
            visit.afterHoursMultiplier = afterHoursMultiplier
        }
    }
}
