import SwiftUI
import SwiftData

/// The Work Log: every job in the Service Log across all clients, for a
/// period, grouped by day, with what it came to (`WorkLog`). Opened from
/// Home's Quick Actions. Viewing is never gated; a job's page keeps its own.
struct WorkLogView: View {
    @Environment(AuthManager.self) private var authManager

    /// Remembered; custom dates and the other filters start afresh.
    @AppStorage("workLogPeriod") private var periodRaw = WorkLog.Period.thisWeek.rawValue
    @State private var customStart = Calendar.current.startOfDay(for: .now)
    @State private var customEnd = Calendar.current.startOfDay(for: .now)
    @State private var service: WorkLog.ServiceKey?
    @State private var billing: WorkLog.BillingFilter = .all

    private var period: WorkLog.Period { WorkLog.Period(rawValue: periodRaw) ?? .thisWeek }

    var body: some View {
        WorkLogList(operatorID: authManager.userID,
                    period: period,
                    interval: period.interval(now: .now, custom: (customStart, customEnd)),
                    periodRaw: $periodRaw,
                    customStart: $customStart, customEnd: $customEnd,
                    service: $service, billing: $billing)
            .navigationTitle("Work Log")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The list for one period: a fetch bounded by the business and the dates,
/// as Service History bounds its own by client, then the filters in memory.
private struct WorkLogList: View {
    let operatorID: String
    let period: WorkLog.Period
    @Binding var periodRaw: String
    @Binding var customStart: Date
    @Binding var customEnd: Date
    @Binding var service: WorkLog.ServiceKey?
    @Binding var billing: WorkLog.BillingFilter

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [ServiceRecord]
    @Query private var clients: [Client]

    init(operatorID: String, period: WorkLog.Period, interval: DateInterval, periodRaw: Binding<String>,
         customStart: Binding<Date>, customEnd: Binding<Date>,
         service: Binding<WorkLog.ServiceKey?>, billing: Binding<WorkLog.BillingFilter>) {
        self.operatorID = operatorID
        self.period = period
        _periodRaw = periodRaw
        _customStart = customStart
        _customEnd = customEnd
        _service = service
        _billing = billing
        let id = operatorID
        let start = interval.start, end = interval.end
        _records = Query(filter: #Predicate<ServiceRecord> {
            $0.operatorID == id && $0.performedAt >= start && $0.performedAt < end
        }, sort: \.performedAt, order: .reverse)
        _clients = Query(filter: #Predicate<Client> { $0.operatorID == id })
    }

    var body: some View {
        // Looked up once for the list, not once a row.
        let invoiceIDs = ServiceLog.invoiceIDs(in: modelContext)
        let contracts = Contracts.all(in: modelContext)
        let services = WorkLog.services(in: records)
        let shown = WorkLog.filter(records, operatorID: operatorID, service: service, billing: billing,
                                   invoiceIDs: invoiceIDs, contracts: contracts)
        let totals = WorkLog.Totals(shown, service: service)
        let clientsByID = Dictionary(clients.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        List {
            if period == .custom {
                Section(title: "Dates") {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                }
                .listRowBackground(PlowRColor.surface)
            }
            if shown.isEmpty {
                ContentUnavailableView {
                    Label("No Work in This Period", systemImage: PlowRSymbol.workLog.name)
                } description: {
                    Text(records.isEmpty
                         ? "Completed stops and visits, and work logged by hand, appear here by day."
                         : "No work matches these filters. Completed stops and visits appear here by day.")
                }
                .listRowBackground(Color.clear)   // the empty state sits on the page
            } else {
                Section {
                    LabeledContent("Jobs", value: "\(totals.count)")
                    LabeledContent("Time", value: ServiceLog.totalTimeText(minutes: totals.minutes))
                    LabeledContent("Value", value: Money.text(totals.value))
                } header: {
                    SectionTitle(LocalizedStringKey(period.title))
                } footer: {
                    SectionNote("At the prices recorded with each job, before discounts, tax and contracts.")
                }
                .listRowBackground(PlowRColor.surface)
                ForEach(WorkLog.days(shown), id: \.day) { group in
                    Section(title: Self.dayTitle(group.day)) {
                        ForEach(group.records) { record in
                            NavigationLink {
                                ServiceRecordDetailView(record: record, client: clientsByID[record.clientID])
                            } label: {
                                WorkLogRow(record: record,
                                           status: WorkLog.status(of: record, invoiceIDs: invoiceIDs,
                                                                  contracts: contracts),
                                           value: WorkLog.value(of: record, service: service))
                            }
                        }
                    }
                    .listRowBackground(PlowRColor.surface)
                }
                .listRowBackground(PlowRColor.surface)
            }
        }
        .plowRGrouped()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu(services: services)
            }
        }
        .onChange(of: customStart) { _, start in
            if customEnd < start { customEnd = start }
        }
        // A service no longer among the period's work stops filtering.
        .onChange(of: services) { _, services in
            if let chosen = service, !services.contains(where: { $0.key == chosen }) { service = nil }
        }
    }

    private var isFiltered: Bool { service != nil || billing != .all }

    /// Period, service ("All Services" and the services in this period's
    /// work) and billing.
    private func filterMenu(services: [WorkLog.ServiceOption]) -> some View {
        Menu {
            Picker("Period", selection: $periodRaw) {
                ForEach(WorkLog.Period.allCases) { period in
                    Text(period.title).tag(period.rawValue)
                }
            }
            .pickerStyle(.inline)
            Picker("Service", selection: $service) {
                Text("All Services").tag(WorkLog.ServiceKey?.none)
                ForEach(services) { option in
                    Text(option.name).tag(WorkLog.ServiceKey?.some(option.key))
                }
            }
            .pickerStyle(.inline)
            Picker("Billing", selection: $billing) {
                ForEach(WorkLog.BillingFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: isFiltered
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter Work Log")
        .accessibilityValue(isFiltered ? "On" : "Off")
    }

    /// "Today", "Yesterday", else "Monday, Nov 23", with the year when it
    /// isn't this year.
    static func dayTitle(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        if calendar.isDate(day, equalTo: now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }
}

/// One job in the Work Log: who, what was done, where it stands with
/// billing, how long, and its recorded value (`WorkLog.value`).
private struct WorkLogRow: View {
    let record: ServiceRecord
    let status: ServiceLog.BillingStatus
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.clientName.isEmpty ? "Client" : record.clientName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(Money.text(value))
                    .font(.subheadline)
            }
            Text(ServiceRecordRow.servicesSummary(of: record))
                .font(.caption)
                .foregroundStyle(PlowRColor.inkSecondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                ServiceRecordStatusChip(status: status)
                if record.minutes >= 1 {
                    Label("\(Int(record.minutes.rounded())) min", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
                if !record.routeName.isEmpty {
                    Label(record.routeName, systemImage: "map")
                        .font(.caption2)
                        .foregroundStyle(PlowRColor.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
