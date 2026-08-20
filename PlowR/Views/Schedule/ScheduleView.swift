import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]
    @Query private var allClients: [Client]

    @State private var selectedDate = Date()
    @State private var showingAddVisit = false
    @State private var visitToEdit: ScheduledVisit?
    @State private var invoicingVisit: ScheduledVisit?
    @State private var showingRouteCreated = false
    @State private var createdRouteName = ""

    // MARK: - Computed Properties

    private var myVisits: [ScheduledVisit] {
        allVisits.filter { $0.operatorID == authManager.userID }
    }

    private var visitsForSelectedDate: [ScheduledVisit] {
        myVisits
            .filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: selectedDate) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var overduePending: [ScheduledVisit] {
        myVisits.filter { $0.isPast }
    }

    // Next 5 scheduled visits after the selected day
    private var upcomingVisits: [ScheduledVisit] {
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return [] }
        let start = Calendar.current.startOfDay(for: nextDay)
        return myVisits
            .filter { $0.status == .scheduled && $0.scheduledDate >= start }
            .prefix(5)
            .map { $0 }
    }

    private func clientForVisit(_ visit: ScheduledVisit) -> Client? {
        allClients.first { $0.id.uuidString == visit.clientID && $0.operatorID == authManager.userID }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                calendarSection
                if Calendar.current.isDateInToday(selectedDate) { overdueSection }
                daySection
                if !upcomingVisits.isEmpty { upcomingSection }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddVisit = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { selectedDate = Date() }
                        .font(.subheadline)
                }
            }
            .sheet(isPresented: $showingAddVisit) {
                AddVisitView(initialDate: selectedDate)
            }
            .sheet(item: $visitToEdit) { visit in
                AddVisitView(editing: visit)
            }
            .sheet(item: $invoicingVisit) { visit in
                if let client = clientForVisit(visit) {
                    NavigationStack {
                        ProposalBuilderView(
                            client: client,
                            isInvoiceMode: true,
                            linkedVisitID: visit.id.uuidString,
                            afterHoursMultiplier: visit.isAfterHours ? visit.afterHoursMultiplier : 1.0
                        )
                    }
                }
            }
            .alert("Route Created", isPresented: $showingRouteCreated) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\"\(createdRouteName)\" has been added to your Routes tab.")
            }
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        Section {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: - Day Section

    private var daySection: some View {
        Section {
            if visitsForSelectedDate.isEmpty {
                Label("Nothing scheduled", systemImage: "calendar.badge.minus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visitsForSelectedDate) { visit in
                    visitRow(visit)
                        .swipeActions(edge: .leading) {
                            if visit.status == .scheduled {
                                Button { markComplete(visit) } label: {
                                    Label("Complete", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(visit)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if visit.status == .scheduled {
                                Button { visit.status = .skipped } label: {
                                    Label("Skip", systemImage: "arrow.right.circle")
                                }
                                .tint(.orange)
                            }
                            if visit.proposalID.isEmpty {
                                Button { invoicingVisit = visit } label: {
                                    Label("Invoice", systemImage: "doc.text.badge.plus")
                                }
                                .tint(.blue)
                            }
                        }
                        .onTapGesture { visitToEdit = visit }
                }
            }
        } header: {
            HStack {
                Label(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                Spacer()
                let scheduledClientVisits = visitsForSelectedDate.filter { $0.status == .scheduled && !$0.clientID.isEmpty }
                if !scheduledClientVisits.isEmpty {
                    Button {
                        createRouteFromSchedule()
                    } label: {
                        Label("Create Route", systemImage: "map.badge.plus")
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                    }
                }
            }
        }
    }

    // MARK: - Overdue Section

    @ViewBuilder
    private var overdueSection: some View {
        let overdue = overduePending.filter {
            !Calendar.current.isDate($0.scheduledDate, inSameDayAs: selectedDate)
        }
        if !overdue.isEmpty {
            Section {
                ForEach(overdue.prefix(3)) { visit in
                    HStack(spacing: 10) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visit.clientName).font(.subheadline.weight(.medium))
                            Text(visit.scheduledDate, style: .date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Complete") { markComplete(visit) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(.green)
                            .controlSize(.small)
                    }
                }
            } header: {
                Label("\(overdue.count) Overdue", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        Section {
            ForEach(upcomingVisits) { visit in
                upcomingVisitRow(visit)
            }
        } header: {
            Label("Upcoming", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }

    // MARK: - Row Views

    private func visitRow(_ visit: ScheduledVisit) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(visit.status.chipColor)
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(visit.clientName)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(visit.scheduledDate, style: .time)
                        .font(.caption).foregroundStyle(.secondary)
                    if visit.estimatedMinutes > 0 {
                        Text("· \(visit.estimatedMinutes) min est.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if visit.isRecurring {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2).foregroundStyle(.blue)
                    }
                }
                if !visit.notes.isEmpty {
                    Text(visit.notes)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Label(visit.status.rawValue, systemImage: visit.status.systemImage)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(visit.status.chipColor.opacity(0.15))
                    .foregroundStyle(visit.status.chipColor)
                    .clipShape(Capsule())

                if !visit.proposalID.isEmpty {
                    Label("Invoiced", systemImage: "doc.text.fill")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.green.opacity(0.12))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
                if visit.isAfterHours {
                    Label("After Hours", systemImage: "moon.fill")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func upcomingVisitRow(_ visit: ScheduledVisit) -> some View {
        Button {
            selectedDate = visit.scheduledDate
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text(visit.scheduledDate.formatted(.dateTime.month(.abbreviated)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(visit.scheduledDate.formatted(.dateTime.day()))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.clientName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text(visit.scheduledDate, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                        if visit.estimatedMinutes > 0 {
                            Text("· \(visit.estimatedMinutes) min")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if visit.isRecurring {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2).foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()

                if !visit.proposalID.isEmpty {
                    Image(systemName: "doc.text.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func createRouteFromSchedule() {
        let dateLabel = selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let name = "Route – \(dateLabel)"
        let route = PlowRoute(name: name, operatorID: authManager.userID)
        modelContext.insert(route)

        let scheduled = visitsForSelectedDate.filter { $0.status == .scheduled }
        var order = 0
        for visit in scheduled {
            if let client = allClients.first(where: { $0.id.uuidString == visit.clientID && $0.operatorID == authManager.userID }) {
                let stop = RouteStop(order: order, client: client)
                stop.route = route
                modelContext.insert(stop)
                order += 1
            }
        }

        createdRouteName = name
        showingRouteCreated = true
    }

    private func markComplete(_ visit: ScheduledVisit) {
        visit.status = .completed
        visit.completedAt = Date()

        if visit.isRecurring, let nextDate = visit.nextOccurrence(after: visit.scheduledDate) {
            let next = ScheduledVisit(
                operatorID: visit.operatorID,
                clientID: visit.clientID,
                clientName: visit.clientName,
                clientAddress: visit.clientAddress,
                scheduledDate: nextDate
            )
            next.estimatedMinutes = visit.estimatedMinutes
            next.notes = visit.notes
            next.isRecurring = visit.isRecurring
            next.recurrenceType = visit.recurrenceType
            next.recurrenceInterval = visit.recurrenceInterval
            next.recurrenceWeekdays = visit.recurrenceWeekdays
            next.recurrenceEndDate = visit.recurrenceEndDate
            next.seriesID = visit.seriesID
            next.isAfterHours = visit.isAfterHours
            next.afterHoursMultiplier = visit.afterHoursMultiplier
            modelContext.insert(next)
        }
    }
}
