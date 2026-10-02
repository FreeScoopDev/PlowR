import SwiftUI
import SwiftData
import CoreLocation

struct DashboardView: View {
    @Environment(ActiveRouteStore.self) private var activeRoute
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager

    @Query private var allProfiles: [BusinessProfile]
    @Query private var allClients: [Client]
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]
    @Query(sort: \PlowRoute.createdAt, order: .reverse) private var allRoutes: [PlowRoute]
    @Query private var allProposals: [Proposal]
    @Query private var allRecords: [ServiceRecord]
    @Query private var allContracts: [Contract]
    @Query private var allServices: [ServiceItem]
    @Query private var allChecks: [TriggerCheck]

    @State private var dashWeather: WeatherCondition?
    /// The coming days' forecast, for the storm card.
    @State private var forecastDays: [DayForecast] = []
    /// Stand-in stops for the storm card's text (the message screen works
    /// from stops). Never saved.
    @State private var stormTextStops: [RouteStop]?
    private let iCloud = ICloudStatus.shared

    @State private var showingSettings = false
    @State private var showingAddClient = false
    @State private var showingContactScanner = false
    @State private var showingCreateRoute = false
    @State private var showingAddVisit = false

    // MARK: - Derived Data

    private var profile: BusinessProfile? {
        allProfiles.first { $0.operatorID == authManager.userID }
    }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }
    }

    private var myProposals: [Proposal] {
        allProposals.filter { $0.operatorID == authManager.userID }
    }

    private var todayVisits: [ScheduledVisit] {
        allVisits.filter {
            $0.operatorID == authManager.userID &&
            $0.status == .scheduled &&
            Calendar.current.isDateInToday($0.scheduledDate)
        }
    }

    private var upcomingVisits: [ScheduledVisit] {
        let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let weekEnd  = tomorrow.addingTimeInterval(86400 * 7)
        return allVisits.filter {
            $0.operatorID == authManager.userID &&
            $0.status == .scheduled &&
            $0.scheduledDate >= tomorrow &&
            $0.scheduledDate < weekEnd
        }.prefix(5).map { $0 }
    }

    private var recentRoutes: [PlowRoute] {
        allRoutes.filter { $0.operatorID == authManager.userID }.prefix(3).map { $0 }
    }

    private var outstandingBalance: Double {
        Payments.owed(myProposals)
    }

    /// A storm coming, if the business offers a snow service or has a
    /// contract trigger (StormWatch).
    private var storm: StormWatch.Storm? {
        StormWatch.storm(in: forecastDays, book: StormWatch.Book(
            contracts: allContracts, services: allServices,
            activeClientIDs: Set(myClients.filter(\.isActive).map(\.id.uuidString)),
            operatorID: authManager.userID, checks: allChecks))
    }

    private var myRoutes: [PlowRoute] {
        allRoutes.filter { $0.operatorID == authManager.userID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var overdueCount: Int { myProposals.filter { $0.invoiceStatus == .overdue }.count }
    private var draftCount:   Int { myProposals.filter { $0.invoiceStatus == .draft   }.count }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    iCloudBanner
                    profileCard
                    if let w = dashWeather { dashWeatherStrip(w) }
                    if let storm {
                        StormCard(storm: storm, routes: myRoutes, clients: myClients, text: { clients in
                            stormTextStops = clients.enumerated().map { RouteStop(order: $0.offset, client: $0.element) }
                        }, mark: { trigger, below in
                            markBelowTrigger(trigger, on: storm.day, below: below)
                        })
                    }
                    todayCard
                    financeRow
                    readyToSendRow
                    pipelineRow
                    routesCard
                    if !upcomingVisits.isEmpty { upcomingCard }
                    quickActionsGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showingAddClient)  { AddClientView() }
        .sheet(isPresented: $showingContactScanner) { ContactScannerView() }
        .sheet(isPresented: $showingCreateRoute) { CreateRouteView() }
        .sheet(isPresented: $showingAddVisit)   { AddVisitView() }
        .sheet(isPresented: Binding(get: { stormTextStops != nil }, set: { if !$0 { stormTextStops = nil } })) {
            MassMessageView(stops: stormTextStops ?? [], allClients: myClients,
                            presets: StormCard.presets, kind: .text)
        }
        .task {
            iCloud.watch()
            NotificationService.shared.requestAuthorization()
            NotificationService.shared.scheduleOverdueReminder(count: overdueCount)
            await fetchDashboardWeather()
        }
    }

    // MARK: - iCloud

    /// Said once, in place, and closable. It used to be an alert that came
    /// back every time the Dashboard appeared, and only when the iCloud
    /// database failed to open, never for a user not signed in to iCloud.
    @ViewBuilder
    private var iCloudBanner: some View {
        if let banner = iCloud.banner {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(banner.title)
                        .font(.subheadline.weight(.semibold))
                    Text(banner.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    iCloud.dismissBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)     // In gloves, too.
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Hide")
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        }
    }

    /// The storm card's mark: the client's contracted places, that day.
    private func markBelowTrigger(_ trigger: StormWatch.Trigger, on day: Date, below: Bool) {
        if below {
            TriggerChecks.mark(clientID: trigger.clientID, clientName: trigger.clientName,
                               places: TriggerChecks.contractPlaces(of: trigger.clientID, on: day, contracts: allContracts,
                                                                    services: allServices),
                               on: day, operatorID: authManager.userID, in: modelContext)
        } else {
            TriggerChecks.unmark(trigger.clientID, on: day, in: modelContext)
        }
    }

    // MARK: - Weather

    @ViewBuilder
    private func dashWeatherStrip(_ w: WeatherCondition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: w.symbolName)
            Text("\(Int(w.temperatureF))°F")
                .fontWeight(.semibold)
            Text("·")
            Text(w.description)
            Spacer()
            Text("\(Int(w.windSpeedMph)) mph \(w.windDirectionLabel)")
                .foregroundStyle(.white.opacity(0.75))
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(WeatherKind(w.description).background)
        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        .onTapGesture {
            if let url = URL(string: "weather://"), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func fetchDashboardWeather() async {
        let clManager = CLLocationManager()
        let status = clManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse,
              let loc = clManager.location else { return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        async let currentWeather = WeatherService.shared.fetch(latitude: lat, longitude: lon)
        async let forecast = WeatherService.shared.fetchForecast(latitude: lat, longitude: lon)
        dashWeather = try? await currentWeather
        if let days = try? await forecast {
            forecastDays = days
            NotificationService.shared.scheduleWeatherAlert(for: days, storm: storm)
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 14) {
            logoMark.frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.companyName.dashNilIfEmpty ?? "My Business")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Group {
                    if let tagline = profile?.tagline.dashNilIfEmpty {
                        Text(tagline)
                    } else {
                        Text("\(myClients.count) client\(myClients.count == 1 ? "" : "s")")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
    }

    @ViewBuilder
    private var logoMark: some View {
        if let data = profile?.logoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous)
                .fill(Color.accentColor.gradient)
                .overlay {
                    Text((profile?.companyName ?? "").dashInitials)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Today", icon: "calendar",
                          badge: todayVisits.isEmpty ? nil : "\(todayVisits.count)",
                          badgeColor: .blue)

            DashCard {
                if todayVisits.isEmpty {
                    emptyRow("No visits scheduled today", icon: "calendar.badge.plus")
                } else {
                    ForEach(Array(todayVisits.prefix(5).enumerated()), id: \.element.id) { i, visit in
                        if i > 0 { Divider().padding(.leading, Self.rowTextInset) }
                        visitRow(visit)
                    }
                    if todayVisits.count > 5 {
                        Divider()
                        Text("+ \(todayVisits.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func visitRow(_ visit: ScheduledVisit) -> some View {
        let client = allClients.first { $0.id.uuidString == visit.clientID }
        return Group {
            if let client {
                NavigationLink { EditClientView(client: client) } label: {
                    visitRowContent(visit)
                }
                .buttonStyle(.plain)
            } else {
                visitRowContent(visit)
            }
        }
    }

    /// Where a row's text starts (row padding, icon or date column, gap), so
    /// a separator lines up with it, as iOS lists do. The separators used to
    /// start 10 and 6 points short.
    private static let rowTextInset: CGFloat = 14 + 28 + 12
    private static let dateRowTextInset: CGFloat = 14 + 36 + 12

    private func visitRowContent(_ visit: ScheduledVisit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.circle.fill")
                .font(.title3)
                .foregroundStyle(visit.status.chipColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(visit.clientName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(visit.scheduledDate, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if visit.estimatedMinutes > 0 {
                Text("\(visit.estimatedMinutes)m").font(.caption2).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Finances

    private var financeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Finances", icon: "dollarsign.circle",
                          badge: overdueCount > 0 ? "\(overdueCount) overdue" : nil,
                          badgeColor: .red)
            StatTileRow {
                // Outstanding opens what's owed by how late it is.
                NavigationLink {
                    MoneyOwedView()
                } label: {
                    StatTile(
                        value: outstandingBalance.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                        label: "Outstanding",
                        color: outstandingBalance > 0 ? .orange : .secondary
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ProposalListView(initialFilter: .overdue)
                } label: {
                    StatTile(value: "\(overdueCount)", label: "Overdue",
                             color: overdueCount > 0 ? .red : .secondary)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ProposalListView(initialFilter: .draft)
                } label: {
                    StatTile(value: "\(draftCount)", label: "Drafts",
                             color: draftCount > 0 ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Contract payments

    /// Contract payments due (Make Invoices makes their drafts here, on
    /// this device), and drafts made and waiting to be sent.
    @ViewBuilder
    private var readyToSendRow: some View {
        let due = ContractInstallments.allDue(allContracts, operatorID: authManager.userID)
        let ready = ContractInstallments.readyToSend(allProposals, operatorID: authManager.userID)
        if !due.isEmpty || !ready.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Contract Payments", icon: "doc.text")
                DashCard {
                    if !due.isEmpty {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "calendar.badge.clock", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(due.count == 1 ? "1 payment due" : "\(due.count) payments due")
                                    .font(.subheadline.weight(.semibold))
                                Text(due.reduce(0) { $0 + $1.installment.amount }.formatted(.currency(code: "USD")))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(due.count == 1 ? "Make Invoice" : "Make Invoices") {
                                ContractInstallments.makeAllDue(operatorID: authManager.userID, in: modelContext)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(14)
                    }
                    if !ready.isEmpty {
                        if !due.isEmpty { Divider().padding(.leading, 14) }
                        NavigationLink { ProposalListView(initialFilter: .draft) } label: {
                            HStack(spacing: 12) {
                                IconBadge(systemImage: "doc.text.fill", color: .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ready.count == 1 ? "1 invoice ready to send" : "\(ready.count) invoices ready to send")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(Payments.owed(ready).formatted(.currency(code: "USD"))) · in Drafts")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Pipeline

    /// Clients who aren't customers yet (Pipeline).
    private var pipeline: [Pipeline.Entry] {
        Pipeline.entries(allClients, operatorID: authManager.userID,
                         facts: Pipeline.Facts(documents: allProposals, records: allRecords, visits: allVisits,
                                               stops: allRoutes.flatMap { $0.stops ?? [] }))
    }

    /// Leads, quotes and follow-ups, when there are any: each opens the Pipeline.
    @ViewBuilder
    private var pipelineRow: some View {
        let entries = pipeline.filter { $0.stage != .lost }
        if !entries.isEmpty {
            let followUps = entries.filter(\.needsFollowUp).count
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Pipeline", icon: "person.crop.circle.badge.plus",
                              badge: followUps > 0 ? "\(followUps) to follow up" : nil, badgeColor: .orange)
                let leads = entries.filter { $0.stage == .lead }.count
                let quoted = entries.filter { $0.stage == .quoted }.count
                // Each its own link to the Pipeline, and zero in grey, as the finance tiles.
                StatTileRow {
                    NavigationLink { PipelineView() } label: {
                        StatTile(value: "\(leads)", label: "Leads", color: leads > 0 ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { PipelineView() } label: {
                        StatTile(value: "\(quoted)", label: "Quoted", color: quoted > 0 ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { PipelineView() } label: {
                        StatTile(value: "\(followUps)", label: "Follow Up", color: followUps > 0 ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Routes

    private var routesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Routes", icon: "map")

            DashCard {
                if recentRoutes.isEmpty {
                    emptyRow("No routes yet", icon: "map.badge.plus")
                } else {
                    ForEach(Array(recentRoutes.enumerated()), id: \.element.id) { i, route in
                        if i > 0 { Divider().padding(.leading, Self.rowTextInset) }
                        NavigationLink { RouteDetailView(route: route) } label: {
                            routeRow(route)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func routeRow(_ route: PlowRoute) -> some View {
        let run = RouteRunSummary(route: route, store: activeRoute)
        let total = run.total
        let done = run.done
        let isActive = run.isRunning
        let isDone = run.isDone

        return HStack(spacing: 12) {
            Image(systemName: isActive ? "map.fill"
                             : (isDone ? "checkmark.circle.fill" : "map"))
                .font(.title3)
                .foregroundStyle(isActive ? .orange : (isDone ? .green : .secondary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(route.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(total == 0  ? "No stops"
                     : isDone    ? "Completed"
                     : done == 0 ? "\(total) stop\(total == 1 ? "" : "s")"
                                 : "\(done)/\(total) complete")
                    .font(.caption)
                    .foregroundStyle(isActive ? .orange : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Upcoming

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Coming Up", icon: "calendar.badge.clock")
            DashCard {
                ForEach(Array(upcomingVisits.enumerated()), id: \.element.id) { i, visit in
                    if i > 0 { Divider().padding(.leading, Self.dateRowTextInset) }
                    let client = allClients.first { $0.id.uuidString == visit.clientID }
                    let rowContent = upcomingVisitRow(visit)
                    if let client {
                        NavigationLink { EditClientView(client: client) } label: { rowContent }
                            .buttonStyle(.plain)
                    } else {
                        rowContent
                    }
                }
            }
        }
    }

    private func upcomingVisitRow(_ visit: ScheduledVisit) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(visit.scheduledDate, format: .dateTime.weekday(.abbreviated))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(visit.scheduledDate, format: .dateTime.day())
                    .font(.title3.weight(.bold))
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(visit.clientName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(visit.scheduledDate, style: .time)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if visit.isAfterHours {
                Image(systemName: "moon.fill").font(.caption2).foregroundStyle(.indigo)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Quick Actions

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Quick Actions", icon: "bolt.fill")
            // Four actions, a full 2 × 2. Settings is the gear at the top.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: PlowRLayout.tileSpacing),
                                GridItem(.flexible(), spacing: PlowRLayout.tileSpacing)],
                      spacing: PlowRLayout.tileSpacing) {
                Menu {
                    Button { showingAddClient = true } label: {
                        Label("Add Manually", systemImage: "person.badge.plus")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingContactScanner = true } label: {
                            Label("Scan with Camera", systemImage: "camera.viewfinder")
                        }
                    }
                } label: {
                    quickActionLabel("New Client", icon: "person.badge.plus", color: .blue)
                }
                .buttonStyle(.plain)
                quickAction("New Route",       icon: "map.badge.plus",      color: .green)  { showingCreateRoute = true }
                quickAction("Schedule Visit",  icon: "calendar.badge.plus", color: .orange) { showingAddVisit = true }
                NavigationLink { ClientStatsView() } label: {
                    quickActionLabel("Season Report", icon: "chart.bar.doc.horizontal", color: .indigo)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickActionLabel(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22, alignment: .center)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
    }

    private func quickAction(_ title: String, icon: String, color: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            quickActionLabel(title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Helpers

    private func sectionHeader(_ title: String, icon: String,
                                badge: String? = nil, badgeColor: Color = .orange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            if let badge {
                StatusChip(badge, color: badgeColor)
            }
            Spacer()
        }
    }

    private func emptyRow(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}

// MARK: - Card Container

/// A Dashboard card's container; the storm card uses it too.
struct DashCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
    }
}

// MARK: - String Helpers (file-private)

private extension String {
    var dashNilIfEmpty: String? { isEmpty ? nil : self }
    var dashInitials: String {
        split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
            .dashNilIfEmpty ?? "P"
    }
}
