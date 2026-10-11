import SwiftUI
import SwiftData
import CoreLocation
import UserNotifications

struct DashboardView: View {
    @Environment(ActiveRouteStore.self) private var activeRoute
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.access) private var access

    @Query private var allProfiles: [BusinessProfile]
    @Query private var allClients: [Client]
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]
    @Query(sort: \PlowRoute.createdAt, order: .reverse) private var allRoutes: [PlowRoute]
    @Query private var allProposals: [Proposal]
    @Query private var allRecords: [ServiceRecord]
    @Query private var allContracts: [Contract]
    @Query private var allServices: [ServiceItem]
    @Query private var allChecks: [TriggerCheck]

    /// An invoice paid more than its total, its payments open (needsALookRows).
    @State private var overpaidInvoice: Proposal?
    @State private var dashWeather: WeatherCondition?
    /// The coming days' forecast, for the storm card.
    @State private var forecastDays: [DayForecast] = []
    /// Stand-in stops for the storm card's text (the message screen works
    /// from stops). Never saved.
    @State private var stormTextStops: [RouteStop]?
    private let iCloud = ICloudStatus.shared

    /// Today, refreshed when the app comes back and when the day changes:
    /// left open overnight, the page said yesterday's date.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    /// Notifications not yet asked about (Get Started offers them).
    @State private var alertsUndecided = false
    /// The Get Started card was hidden (FirstRun.checklistHiddenKey).
    @State private var checklistHidden = false

    @State private var showingSettings = false
    @State private var gate: ProGate?
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
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: now)
        }
    }

    private var upcomingVisits: [ScheduledVisit] {
        let tomorrow = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        let weekEnd  = tomorrow.addingTimeInterval(86400 * 7)
        return allVisits.filter {
            $0.operatorID == authManager.userID &&
            $0.status == .scheduled &&
            $0.scheduledDate >= tomorrow &&
            $0.scheduledDate < weekEnd
        }.prefix(5).map { $0 }
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

    // MARK: - Today, first (Joe, 2026-10-11)

    /// Can the plan start `route` (Access: free runs only the oldest).
    private func canStart(_ route: PlowRoute) -> Bool {
        access.canStartRoute(route, among: allRoutes, operatorID: authManager.userID)
    }

    /// What's waiting on the business, in order (DashboardToday.attention),
    /// with the first record of each kind to check, worked out once.
    private struct Waiting {
        var items: [DashboardAttention]
        var firstBilledTwice: Proposal?
        var firstOverpaid: Proposal?
    }

    private var waiting: Waiting {
        let overdue = myProposals.filter { $0.invoiceStatus == .overdue }
        let due = ContractInstallments.allDue(allContracts, operatorID: authManager.userID)
        let drafts = myProposals.filter { $0.isInvoice && $0.invoiceStatus == .draft }
        let billedTwice = ContractInstallments.duplicates(myProposals, operatorID: authManager.userID)
        let overpaid = Payments.overpaid(myProposals)
        let items = DashboardToday.attention(
            overdue: (overdue.count, Payments.balance(of: overdue)),
            paymentsDue: (due.count, ContractInstallments.amountDue(due)),
            readyToSend: (drafts.count, Payments.balance(of: drafts)),
            followUps: pipeline.filter(\.needsFollowUp).count,
            billedTwice: billedTwice.count,
            overpaid: overpaid.count)
        return Waiting(items: items, firstBilledTwice: billedTwice.first, firstOverpaid: overpaid.first)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PlowRLayout.space4) {
                    header
                    getStarted
                    iCloudBanner
                    ProStatusBanner()
                    if let storm {
                        // The forecast for everyone; its tools are PlowR Pro.
                        StormCard(storm: storm, routes: myRoutes, clients: myClients, text: { clients in
                            $gate.unless(ProGate.proFeature("Texting clients from the storm card", access)) {
                                stormTextStops = clients.enumerated().map { RouteStop(order: $0.offset, client: $0.element) }
                            }
                        }, mark: { trigger, below in
                            // Marking is Pro; taking a mark off never is (as on the contract page).
                            $gate.unless(below ? ProGate.proFeature("Marking below trigger", access) : nil) {
                                markBelowTrigger(trigger, on: storm.day, below: below)
                            }
                        })
                        if dashWeather == nil {
                            WeatherAttribution().frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    todayCard
                    needsYouSection
                    moneySection
                    pipelineRow
                    if !upcomingVisits.isEmpty { upcomingCard }
                    quickActionsGrid
                }
                .padding(.horizontal, PlowRLayout.space4)
                .padding(.top, PlowRLayout.space1)
                .padding(.bottom, PlowRLayout.space6 + PlowRLayout.space2)
            }
            // Cards fade under the gear and the clock as they scroll, as
            // under a navigation bar: with no title, nothing else does.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .background(PlowRColor.ground)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            // The page's own heading (the date and the business) says where
            // you are: Barlow can't go in iOS 26's title (CLAUDE.md).
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: PlowRSymbol.settings.name)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .onChange(of: access.plan, initial: true) { _, plan in ProStatusBanner.reopenOnSubscribe(plan) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
        .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showingAddClient)  { AddClientView() }
        .proGateSheet($gate)
        .sheet(isPresented: $showingContactScanner) { ContactScannerView() }
        .sheet(isPresented: $showingCreateRoute) { CreateRouteView() }
        .sheet(isPresented: $showingAddVisit)   { AddVisitView() }
        .sheet(isPresented: Binding(get: { stormTextStops != nil }, set: { if !$0 { stormTextStops = nil } })) {
            MassMessageView(stops: stormTextStops ?? [], allClients: myClients,
                            presets: StormCard.presets, kind: .text)
        }
        // Payments open as a sheet, as from an invoice's page.
        .sheet(item: $overpaidInvoice) { InvoicePaymentsView(invoice: $0) }
        .task {
            iCloud.watch()
            // Notifications are asked for in setup and from Get Started,
            // with why: the alert used to appear the moment Home did.
            alertsUndecided = await UNUserNotificationCenter.current().notificationSettings()
                .authorizationStatus == .notDetermined
            checklistHidden = UserDefaults.standard.bool(forKey: FirstRun.checklistHiddenKey(authManager.userID))
            NotificationService.shared.scheduleOverdueReminder(count: overdueCount)
            await fetchDashboardWeather()
        }
    }

    // MARK: - Header

    /// The day, the business (its profile, a tap away) and the weather.
    /// It replaces the profile card and the weather strip.
    private var header: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space1) {
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(PlowRFont.label)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(PlowRColor.inkSecondary)
            NavigationLink { BusinessProfileView() } label: {
                HStack(spacing: PlowRLayout.space2) {
                    Text(profile?.companyName.dashNilIfEmpty ?? "My Business")
                        .font(PlowRFont.screenTitle)
                        .foregroundStyle(PlowRColor.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlowRColor.inkSecondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your business profile")
            .accessibilityAddTraits(.isHeader)
            if let w = dashWeather {
                Button { openWeather() } label: {
                    HStack(spacing: PlowRLayout.space2) {
                        Image(systemName: w.symbolName)
                            .foregroundStyle(WeatherKind(w.description).iconColor)
                        Text("\(Int(w.temperatureF))°F").font(PlowRFont.number)
                        Text(w.description)
                        Text("· \(Int(w.windSpeedMph)) mph \(w.windDirectionLabel)")
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(PlowRColor.ink)
                    .frame(minHeight: PlowRLayout.minTapTarget)
                }
                .buttonStyle(.plain)
            }
            // WeatherKit's attribution, under the conditions it supplied (the
            // storm card's forecast alone gets it under the card).
            if dashWeather != nil {
                WeatherAttribution()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openWeather() {
        if let url = URL(string: "weather://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Get Started

    @ViewBuilder
    private var getStarted: some View {
        let checklist = FirstRun.checklist(profile: profile, clients: myClients.count, routes: myRoutes.count,
                                           documents: myProposals, alertsUndecided: alertsUndecided)
        if !checklistHidden && !checklist.isComplete {
            GetStartedCard(checklist: checklist,
                           addClient: { $gate.unless(ProGate.addClient(access)) { showingAddClient = true } },
                           newRoute: {
                               $gate.unless(ProGate.createRoute(access, routes: allRoutes, operatorID: authManager.userID)) {
                                   showingCreateRoute = true
                               }
                           },
                           hide: {
                               UserDefaults.standard.set(true, forKey: FirstRun.checklistHiddenKey(authManager.userID))
                               withAnimation { checklistHidden = true }
                           },
                           alertsUndecided: $alertsUndecided)
        }
    }

    // MARK: - iCloud

    /// Said once, in place, and closable. It used to be an alert that came
    /// back every time the Dashboard appeared, and only when the iCloud
    /// database failed to open, never for a user not signed in to iCloud.
    @ViewBuilder
    private var iCloudBanner: some View {
        if let banner = iCloud.banner {
            PlowRCard {
                HStack(alignment: .top, spacing: PlowRLayout.space3) {
                    IconBadge(systemImage: "icloud.slash", status: .owed, size: 36)
                    VStack(alignment: .leading, spacing: PlowRLayout.space1) {
                        Text(banner.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PlowRColor.ink)
                        Text(banner.message)
                            .font(.caption)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        iCloud.dismissBanner()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PlowRColor.inkSecondary)
                            .frame(minWidth: PlowRLayout.minTapTarget, minHeight: PlowRLayout.minTapTarget)  // In gloves, too.
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Hide")
                }
                .padding(PlowRLayout.space3)
            }
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

    // MARK: - Today

    /// Today's route, ready to start, and today's visits. The route's page
    /// is where a run starts (skip a stop today, below trigger, the
    /// load-out), so the copper button opens it rather than starting blind.
    private var todayCard: some View {
        let runs = lastRuns
        let leadRoute = DashboardToday.leadRoute(myRoutes, lastRuns: runs, canStart: canStart)
        return VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            sectionLabel("Today", badge: todayVisits.isEmpty ? nil : "\(todayVisits.count) visit\(todayVisits.count == 1 ? "" : "s")")
            PlowRCard {
                if let route = leadRoute {
                    leadRouteRow(route, lastRuns: runs)
                } else if todayVisits.isEmpty {
                    nothingToday
                }
                if !todayVisits.isEmpty {
                    if leadRoute != nil { Divider().overlay(PlowRColor.line) }
                    ForEach(Array(todayVisits.prefix(5).enumerated()), id: \.element.id) { i, visit in
                        if i > 0 { Divider().overlay(PlowRColor.line).padding(.leading, Self.rowTextInset) }
                        visitRow(visit)
                    }
                    if todayVisits.count > 5 {
                        Divider().overlay(PlowRColor.line)
                        Text("+ \(todayVisits.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(PlowRColor.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, PlowRLayout.space2)
                    }
                }
            }
        }
    }

    private var lastRuns: [String: Date] { RouteFacts.lastRuns(in: allRecords) }

    private func leadRouteRow(_ route: PlowRoute, lastRuns: [String: Date]) -> some View {
        let run = RouteRunSummary(route: route, store: activeRoute)
        let minutes = RouteFacts.estimatedMinutes(of: RouteRunSummary.stops(of: route, store: activeRoute),
                                                  clients: myClients)
        let others = myRoutes.count - 1
        let state = DashboardToday.leadState(done: run.done, total: run.total, isDone: run.isDone,
                                             lastRun: lastRuns[route.id.uuidString], canStart: canStart(route),
                                             now: now)
        return VStack(alignment: .leading, spacing: PlowRLayout.space3) {
            HStack(alignment: .firstTextBaseline) {
                Text(route.name)
                    .font(PlowRFont.title)
                    .foregroundStyle(PlowRColor.ink)
                    .lineLimit(2)
                Spacer(minLength: PlowRLayout.space2)
                Text(run.total == 0 ? "No stops"
                     : "\(run.total) stop\(run.total == 1 ? "" : "s")" + (minutes > 0 ? " · \(RouteFacts.duration(minutes))" : ""))
                    .font(.subheadline)
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
            switch state {
            case .doneToday:
                StatusChip("Done today · \(run.total) of \(run.total)", systemImage: PlowRSymbol.complete.name, status: .done)
            case let .partlyDone(done, total):
                StatusChip("\(done) of \(total) done today", status: .owed)
            case .ready, .locked:
                EmptyView()
            }
            // The route's page is where a run starts (and where the plan says
            // why one can't): a route ready to go gets the copper button.
            if state == .ready && run.total > 0 {
                NavigationLink { RouteDetailView(route: route) } label: {
                    Label("Start Route", systemImage: PlowRSymbol.route.name)
                }
                .buttonStyle(.plowRAction)
            } else {
                NavigationLink { RouteDetailView(route: route) } label: {
                    Label(run.total == 0 ? "Add Stops" : "Open Route", systemImage: PlowRSymbol.route.name)
                }
                .buttonStyle(.plowRSecondary)
            }
            if others > 0 {
                NavigationLink { RouteListView() } label: {
                    Text(others == 1 ? "1 other route" : "\(others) other routes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlowRColor.brand)
                        .frame(minHeight: PlowRLayout.minTapTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PlowRLayout.space4)
    }

    /// No route and nothing booked: the two ways to put something on.
    private var nothingToday: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space3) {
            Text("Nothing on today")
                .font(.body.weight(.semibold))
                .foregroundStyle(PlowRColor.ink)
            HStack(spacing: PlowRLayout.space2) {
                Button {
                    $gate.unless(ProGate.createRoute(access, routes: allRoutes, operatorID: authManager.userID)) {
                        showingCreateRoute = true
                    }
                } label: {
                    Label("New Route", systemImage: PlowRSymbol.route.name)
                }
                .buttonStyle(.plowRSecondary)
                Button { showingAddVisit = true } label: {
                    Label("Schedule Visit", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.plowRSecondary)
            }
        }
        .padding(PlowRLayout.space4)
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

    /// Where a row's text starts (row padding, icon column, gap), so a
    /// separator lines up with it, as iOS lists do.
    private static let rowTextInset: CGFloat = PlowRLayout.space4 + 36 + PlowRLayout.space3

    private func visitRowContent(_ visit: ScheduledVisit) -> some View {
        HStack(spacing: PlowRLayout.space3) {
            IconBadge(systemImage: PlowRSymbol.schedule.name, status: visit.status.chipStatus, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.clientName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlowRColor.ink)
                    .lineLimit(1)
                Text(visit.scheduledDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
            Spacer()
            if visit.estimatedMinutes > 0 {
                Text("\(visit.estimatedMinutes)m").font(.caption).foregroundStyle(PlowRColor.inkSecondary)
            }
            chevron
        }
        .padding(.horizontal, PlowRLayout.space4)
        .padding(.vertical, PlowRLayout.space3)
        .contentShape(Rectangle())
    }

    // MARK: - Needs you

    /// What's waiting on the business, each opening where it's dealt with.
    /// With nothing waiting it says so, so an empty section isn't mistaken
    /// for one that didn't load.
    private var needsYouSection: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            sectionLabel("Needs You")
            PlowRCard {
                let waiting = waiting
                let items = waiting.items
                if items.isEmpty {
                    HStack(spacing: PlowRLayout.space3) {
                        IconBadge(systemImage: PlowRSymbol.complete.name, status: .done, size: 36)
                        Text("All caught up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PlowRColor.ink)
                        Spacer()
                    }
                    .padding(PlowRLayout.space4)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Divider().overlay(PlowRColor.line).padding(.leading, Self.rowTextInset) }
                        attentionRow(item, waiting: waiting)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attentionRow(_ item: DashboardAttention, waiting: Waiting) -> some View {
        switch item.kind {
        case .overdue:
            NavigationLink { ProposalListView(initialFilter: .overdue) } label: {
                attentionContent(item, symbol: "exclamationmark.circle.fill", status: .overdue)
            }
            .buttonStyle(.plain)
        case .paymentsDue:
            HStack(spacing: PlowRLayout.space3) {
                attentionText(item, symbol: "calendar.badge.clock", status: .owed)
                Button {
                    $gate.unless(ProGate.edit(access)) {
                        ContractInstallments.makeAllDue(operatorID: authManager.userID, in: modelContext)
                    }
                } label: {
                    Text(item.count == 1 ? "Make Invoice" : "Make Invoices")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlowRColor.brand)
                        .frame(minHeight: PlowRLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, PlowRLayout.space4)
            .padding(.vertical, PlowRLayout.space2)
        case .readyToSend:
            NavigationLink { ProposalListView(initialFilter: .draft) } label: {
                attentionContent(item, symbol: PlowRSymbol.document.name, status: nil)
            }
            .buttonStyle(.plain)
        case .followUps:
            NavigationLink { PipelineView() } label: {
                attentionContent(item, symbol: "clock", status: .owed)
            }
            .buttonStyle(.plain)
        case .billedTwice:
            if let first = waiting.firstBilledTwice {
                NavigationLink { ProposalDetailView(proposal: first) } label: {
                    attentionContent(item, symbol: PlowRSymbol.warning.name, status: .owed,
                                     detail: "\(first.clientName) \(first.invoiceNumber): delete or void one of its invoices.")
                }
                .buttonStyle(.plain)
            }
        case .overpaid:
            if let first = waiting.firstOverpaid {
                Button { overpaidInvoice = first } label: {
                    attentionContent(item, symbol: PlowRSymbol.warning.name, status: .owed,
                                     detail: "\(first.clientName) \(first.invoiceNumber): a payment may be recorded twice, or the client is owed a credit.")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func attentionContent(_ item: DashboardAttention, symbol: String, status: PlowRColor.Status?,
                                  detail: String? = nil) -> some View {
        HStack(spacing: PlowRLayout.space3) {
            attentionText(item, symbol: symbol, status: status, detail: detail)
            chevron
        }
        .padding(.horizontal, PlowRLayout.space4)
        .padding(.vertical, PlowRLayout.space3)
        .contentShape(Rectangle())
    }

    private func attentionText(_ item: DashboardAttention, symbol: String, status: PlowRColor.Status?,
                               detail: String? = nil) -> some View {
        HStack(spacing: PlowRLayout.space3) {
            IconBadge(systemImage: symbol, status: status, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlowRColor.ink)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(PlowRColor.inkSecondary)
                } else if let amount = item.amount, amount > 0 {
                    Text(amount, format: .currency(code: "USD"))
                        .font(.caption)
                        .foregroundStyle(status?.text ?? PlowRColor.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Money

    /// What's owed, and what came in this month.
    private var moneySection: some View {
        let month = Calendar.current.dateInterval(of: .month, for: now)
            ?? DateInterval(start: now, duration: 0)
        let received = Payments.received(myProposals, in: month)
        return VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            sectionLabel("Money")
            StatTileRow {
                // Outstanding opens what's owed by how late it is.
                NavigationLink { MoneyOwedView() } label: {
                    StatTile(value: outstandingBalance.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                             label: "Owed", status: outstandingBalance > 0 ? .owed : nil)
                }
                .buttonStyle(.plain)
                NavigationLink { ClientStatsView() } label: {
                    StatTile(value: received.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                             label: "In this month", status: received > 0 ? .done : nil)
                }
                .buttonStyle(.plain)
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

    /// Leads and quotes, when there are any: each opens the Pipeline.
    /// Follow-ups are in Needs You.
    @ViewBuilder
    private var pipelineRow: some View {
        let entries = pipeline.filter { $0.stage != .lost }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                sectionLabel("Pipeline")
                let leads = entries.filter { $0.stage == .lead }.count
                let quoted = entries.filter { $0.stage == .quoted }.count
                StatTileRow {
                    NavigationLink { PipelineView() } label: {
                        StatTile(value: "\(leads)", label: "Leads", status: leads > 0 ? Pipeline.Stage.lead.chipStatus : nil)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { PipelineView() } label: {
                        StatTile(value: "\(quoted)", label: "Quoted", status: quoted > 0 ? Pipeline.Stage.quoted.chipStatus : nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Upcoming

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            sectionLabel("Coming Up")
            PlowRCard {
                ForEach(Array(upcomingVisits.enumerated()), id: \.element.id) { i, visit in
                    if i > 0 { Divider().overlay(PlowRColor.line).padding(.leading, Self.rowTextInset) }
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
        HStack(spacing: PlowRLayout.space3) {
            VStack(spacing: 0) {
                Text(visit.scheduledDate, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PlowRColor.inkSecondary)
                    .textCase(.uppercase)
                Text(visit.scheduledDate, format: .dateTime.day())
                    .font(PlowRFont.number)
                    .foregroundStyle(PlowRColor.ink)
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.clientName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlowRColor.ink)
                    .lineLimit(1)
                Text(visit.scheduledDate, style: .time)
                    .font(.caption).foregroundStyle(PlowRColor.inkSecondary)
            }
            Spacer()
            if visit.isAfterHours {
                Image(systemName: "moon.fill").font(.caption2).foregroundStyle(PlowRColor.inkSecondary)
                    .accessibilityLabel("After hours")
            }
            chevron
        }
        .padding(.horizontal, PlowRLayout.space4)
        .padding(.vertical, PlowRLayout.space3)
        .contentShape(Rectangle())
    }

    // MARK: - Quick Actions

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            sectionLabel("Quick Actions")
            // Four actions, a full 2 × 2. Settings is the gear at the top.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: PlowRLayout.tileSpacing),
                                GridItem(.flexible(), spacing: PlowRLayout.tileSpacing)],
                      spacing: PlowRLayout.tileSpacing) {
                Menu {
                    Button { $gate.unless(ProGate.addClient(access)) { showingAddClient = true } } label: {
                        Label("Add Manually", systemImage: PlowRSymbol.addClient.name)
                    }
                    if CameraPicker.isAvailable {
                        Button { $gate.unless(ProGate.addClient(access)) { showingContactScanner = true } } label: {
                            Label("Scan with Camera", systemImage: "camera.viewfinder")
                        }
                    }
                } label: {
                    quickActionLabel("New Client", icon: PlowRSymbol.addClient.name)
                }
                .buttonStyle(.plain)
                quickAction("New Route", icon: PlowRSymbol.route.name) {
                    $gate.unless(ProGate.createRoute(access, routes: allRoutes, operatorID: authManager.userID)) { showingCreateRoute = true }
                }
                quickAction("Schedule Visit", icon: "calendar.badge.plus") { showingAddVisit = true }
                NavigationLink { ClientStatsView() } label: {
                    quickActionLabel("Season Report", icon: "chart.bar.doc.horizontal")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickActionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: PlowRLayout.space3) {
            IconBadge(systemImage: icon, size: 32)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PlowRColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(PlowRLayout.space3)
        .frame(minHeight: PlowRLayout.secondaryTapTarget + PlowRLayout.space2)
        .background(PlowRColor.surface,
                    in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous)
            .strokeBorder(PlowRColor.line))
        .contentShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
    }

    private func quickAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            quickActionLabel(title, icon: icon)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Helpers

    /// A section's label: small capitals, as on the route screen, with an
    /// optional count beside it.
    private func sectionLabel(_ title: String, badge: String? = nil) -> some View {
        HStack(spacing: PlowRLayout.space2) {
            Text(title)
                .font(PlowRFont.label)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(PlowRColor.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            if let badge {
                StatusChip(badge, status: .scheduled)
            }
            Spacer()
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(PlowRColor.inkSecondary)
            .accessibilityHidden(true)
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
