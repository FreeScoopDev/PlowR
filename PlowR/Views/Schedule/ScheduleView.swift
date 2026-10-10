import SwiftUI
import SwiftData
import UIKit
import CoreLocation

struct ScheduleView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.access) private var access
    @Query private var allRoutes: [PlowRoute]
    @State private var gate: ProGate?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]
    @Query private var allClients: [Client]

    @State private var selectedDate = Date()
    @State private var weatherFetcher = WeatherFetcher()
    @State private var showingAddVisit = false
    @State private var visitToEdit: ScheduledVisit?
    @State private var invoicingVisit: ScheduledVisit?
    @State private var showingRouteCreated = false
    @State private var createdRouteName = ""
    /// Scheduled visits left off the new route because their client is inactive.
    @State private var skippedInactiveVisits = 0

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

    private var visitDateStrings: Set<String> {
        var strings = Set<String>()
        let cal = Calendar.current
        for visit in myVisits {
            let comps = cal.dateComponents([.year, .month, .day], from: visit.scheduledDate)
            if let y = comps.year, let m = comps.month, let d = comps.day {
                strings.insert(String(format: "%04d-%02d-%02d", y, m, d))
            }
        }
        return strings
    }

    private func clientForVisit(_ visit: ScheduledVisit) -> Client? {
        allClients.first { $0.id.uuidString == visit.clientID && $0.operatorID == authManager.userID }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                weatherSection
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
            .proGateSheet($gate)
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
                            afterHoursMultiplier: visit.priceMultiplier
                        )
                    }
                }
            }
            .alert(createdRouteName.isEmpty ? "No Route Created" : "Route Created", isPresented: $showingRouteCreated) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(routeCreatedMessage)
            }
        }
    }

    // MARK: - Weather Section

    @ViewBuilder
    private var weatherSection: some View {
        if weatherFetcher.isLoading || weatherFetcher.condition != nil {
            Section {
                WeatherBannerRow(fetcher: weatherFetcher)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                // WeatherKit's attribution goes wherever its weather shows.
                if weatherFetcher.condition != nil {
                    WeatherAttribution()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        Section {
            CalendarDotView(selectedDate: $selectedDate, visitDateStrings: visitDateStrings, onLongPress: {
                showingAddVisit = true
            })
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
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
                                Button { $gate.unless(ProGate.edit(access)) { markComplete(visit) } } label: {
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
                                Button { $gate.unless(ProGate.edit(access)) { visit.status = .skipped } } label: {
                                    Label("Skip", systemImage: "arrow.right.circle")
                                }
                                .tint(.orange)
                            }
                            // Not when its work is already on an invoice (Bill
                            // Unbilled Work, Record Services).
                            if visit.proposalID.isEmpty, !ServiceLog.isVisitBilled(visit, in: modelContext) {
                                Button { invoicingVisit = visit } label: {
                                    Label("Invoice", systemImage: "doc.badge.plus")
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
                        $gate.unless(ProGate.createRoute(access, routes: allRoutes, operatorID: authManager.userID)) {
                            createRouteFromSchedule()
                        }
                    } label: {
                        Label("Create Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
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
                        Button("Complete") { $gate.unless(ProGate.edit(access)) { markComplete(visit) } }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(.green)
                            .controlSize(.small)
                    }
                }
            } header: {
                // Styled as the day and Upcoming headers on this screen.
                Label("\(overdue.count) Overdue", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .textCase(nil)
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
            AccentBar(color: visit.status.chipColor)

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
                StatusChip(visit.status.rawValue, systemImage: visit.status.systemImage,
                           color: visit.status.chipColor)
                if !visit.proposalID.isEmpty {
                    StatusChip("Invoiced", systemImage: "doc.text.fill", color: .green)
                }
                if visit.isAfterHours {
                    StatusChip("After Hours", systemImage: "moon.fill", color: .orange)
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
        let scheduled = visitsForSelectedDate.filter { $0.status == .scheduled }
        // Inactive clients are hidden from route building, even with a visit
        // still scheduled from before they were marked inactive.
        let (stops, skipped) = Client.routeStops(for: scheduled, from: allClients, operatorID: authManager.userID)
        skippedInactiveVisits = skipped
        // No stops left: say why instead of saving an empty route.
        guard !stops.isEmpty else {
            createdRouteName = ""
            showingRouteCreated = true
            return
        }
        let route = PlowRoute(name: name, operatorID: authManager.userID)
        modelContext.insert(route)
        for (order, entry) in stops.enumerated() {
            // At the visit's place: the client's own address or a property.
            let stop = RouteStop(order: order, client: entry.client, place: entry.place)
            stop.route = route
            modelContext.insert(stop)
        }
        createdRouteName = name
        showingRouteCreated = true
    }

    /// What Create Route did, including any visits it left off.
    private var routeCreatedMessage: String {
        if createdRouteName.isEmpty {
            return skippedInactiveVisits > 0
                ? "The visits scheduled that day are all for inactive clients or properties."
                : "None of the visits scheduled that day has a client on file."
        }
        var text = "\"\(createdRouteName)\" has been added to your Routes tab."
        if skippedInactiveVisits == 1 {
            text += " 1 visit was left off because its client or property is inactive."
        } else if skippedInactiveVisits > 1 {
            text += " \(skippedInactiveVisits) visits were left off because their clients or properties are inactive."
        }
        return text
    }

    private func markComplete(_ visit: ScheduledVisit) {
        // Also continues the series if it needs a next visit, and records the
        // work in the Service Log.
        ServiceLog.complete(visit, among: allVisits, in: modelContext)
    }
}

// MARK: - Calendar Dot View

private struct CalendarDotView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let visitDateStrings: Set<String>
    var onLongPress: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate, visitDateStrings: visitDateStrings, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let cal = UICalendarView()
        cal.calendar = .current
        cal.locale = .current
        cal.fontDesign = .rounded
        cal.delegate = context.coordinator

        let sel = UICalendarSelectionSingleDate(delegate: context.coordinator)
        cal.selectionBehavior = sel

        let comps = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        sel.setSelected(comps, animated: false)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        cal.addGestureRecognizer(longPress)

        return cal
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.onLongPress = onLongPress
        let old = context.coordinator.visitDateStrings
        let new = visitDateStrings
        if old != new {
            context.coordinator.visitDateStrings = new
            let toReload = old.union(new).compactMap { str -> DateComponents? in
                let parts = str.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                return DateComponents(year: parts[0], month: parts[1], day: parts[2])
            }
            if !toReload.isEmpty {
                uiView.reloadDecorations(forDateComponents: toReload, animated: false)
            }
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        if let sel = uiView.selectionBehavior as? UICalendarSelectionSingleDate {
            let cur = sel.selectedDate
            if cur?.year != comps.year || cur?.month != comps.month || cur?.day != comps.day {
                sel.setSelected(comps, animated: false)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        // No width proposed: the screen's, from the view's own window.
        let width = proposal.width ?? uiView.window?.windowScene?.screen.bounds.width ?? 390
        let height = uiView.sizeThatFits(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        ).height
        return CGSize(width: width, height: max(height, 320))
    }

    class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var selectedDate: Binding<Date>
        var visitDateStrings: Set<String>
        var onLongPress: (() -> Void)?

        init(selectedDate: Binding<Date>, visitDateStrings: Set<String>, onLongPress: (() -> Void)? = nil) {
            self.selectedDate = selectedDate
            self.visitDateStrings = visitDateStrings
            self.onLongPress = onLongPress
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onLongPress?()
        }

        func calendarView(_ calendarView: UICalendarView,
                          decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let y = dateComponents.year,
                  let m = dateComponents.month,
                  let d = dateComponents.day else { return nil }
            let key = String(format: "%04d-%02d-%02d", y, m, d)
            return visitDateStrings.contains(key) ? .default(color: .systemBlue, size: .small) : nil
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate,
                           didSelectDate dateComponents: DateComponents?) {
            guard let dc = dateComponents,
                  let date = Calendar.current.date(from: dc) else { return }
            selectedDate.wrappedValue = date
        }
    }
}

// MARK: - Weather Banner

private struct WeatherBannerRow: View {
    let fetcher: WeatherFetcher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Current conditions
            HStack(spacing: 12) {
                if fetcher.isLoading {
                    ProgressView().controlSize(.small)
                    Text("Checking weather…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let w = fetcher.condition {
                    Image(systemName: w.symbolName)
                        .font(.title2)
                        .foregroundStyle(WeatherKind(w.description).iconColor)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(Int(w.temperatureF))°F")
                                .font(.headline.weight(.semibold))
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(w.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if w.windSpeedMph >= 1 {
                            Text("\(Int(w.windSpeedMph)) mph \(w.windDirectionLabel)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Button { fetcher.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 7-day forecast strip
            if !fetcher.forecast.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(fetcher.forecast, id: \.date) { day in
                            forecastCell(day)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.vertical, 6)
        .onAppear { fetcher.load() }
    }

    private func forecastCell(_ day: DayForecast) -> some View {
        VStack(spacing: 3) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Image(systemName: day.symbolName)
                .font(.subheadline)
                .foregroundStyle(WeatherKind(day.description).iconColor)
            if day.hasSignificantPrecip {
                Text(String(format: "%.1f\"", day.precipitationMm / 25.4))
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
            } else {
                Color.clear.frame(height: 10)
            }
            Text("\(Int(day.maxTempF))°")
                .font(.caption.weight(.semibold))
            Text("\(Int(day.minTempF))°")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 42)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if Calendar.current.isDateInToday(day.date) {
                RoundedRectangle(cornerRadius: PlowRLayout.cornerSmall, style: .continuous)
                    .fill(Color(.systemGray6))
            }
        }
    }

}

@Observable
private final class WeatherFetcher {
    var condition: WeatherCondition?
    var forecast: [DayForecast] = []
    var isLoading = false

    private let locMgr = CLLocationManager()
    private let locDelegate = _LocDelegate()

    init() {
        locMgr.delegate = locDelegate
        locMgr.desiredAccuracy = kCLLocationAccuracyKilometer
        locDelegate.onGotLocation = { [weak self] loc in
            guard let self else { return }
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            Task { @MainActor in
                async let conditionTask = WeatherService.shared.fetch(latitude: lat, longitude: lon)
                async let forecastTask = WeatherService.shared.fetchForecast(latitude: lat, longitude: lon)
                self.condition = try? await conditionTask
                self.forecast = (try? await forecastTask) ?? []
                self.isLoading = false
            }
        }
        locDelegate.onFailed = { [weak self] in
            Task { @MainActor in self?.isLoading = false }
        }
    }

    func load() {
        guard condition == nil && !isLoading else { return }
        isLoading = true
        switch locMgr.authorizationStatus {
        case .notDetermined:
            locMgr.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locMgr.requestLocation()
        default:
            isLoading = false
        }
    }

    func refresh() {
        condition = nil
        load()
    }
}

private final class _LocDelegate: NSObject, CLLocationManagerDelegate {
    var onGotLocation: ((CLLocation) -> Void)?
    var onFailed: (() -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first { onGotLocation?(loc) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            onFailed?()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onFailed?()
    }
}
