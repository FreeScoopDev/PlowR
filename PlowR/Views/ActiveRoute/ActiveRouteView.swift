import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import StoreKit
import MessageUI

/// The in-progress route screen. It shows and drives `ActiveRouteStore`, which
/// owns the route: this view can appear, disappear or be torn down with the app
/// without starting, ending or losing the route.
struct ActiveRouteView: View {
    let route: PlowRoute
    @Environment(ActiveRouteStore.self) private var store
    @Environment(\.access) private var access
    @State private var gate: ProGate?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    @Query private var allClients: [Client]
    @Query private var allServices: [ServiceItem]
    @Query private var allContracts: [Contract]

    @State private var locationManager = LocationManager()
    @State private var showingNotifyPrompt = false
    @State private var showingEndConfirmation = false
    @State private var showingRouteRecap = false
    @State private var showingLocationDeniedAlert = false

    @State private var weather: WeatherCondition? = nil
    /// The weather is the stops', fetched without GPS: a GPS fix replaces it.
    @State private var weatherFromStops = false
    @State private var etaMinutes: Int? = nil
    @State private var showingNavPicker = false
    @State private var navStop: RouteStop? = nil
    /// The stop the service recorder opened for, pinned like the notify
    /// prompt's. Siri or Control Center can complete the stop while the sheet
    /// is up, and a sheet reading the current stop would then have saved this
    /// client's services, photos and invoice on the next one.
    @State private var recorderStop: RouteStop?
    /// The stop being checked and found below its contract's trigger.
    @State private var belowTriggerStop: RouteStop?
    /// What Below Trigger did, acted on once its sheet has closed: iOS won't
    /// present the recap or an alert over a sheet.
    @State private var belowTriggerOutcome: TriggerChecks.PassOutcome?
    /// The stop Below Trigger moved past, for the heads-up offered after it.
    @State private var belowTriggerPassedID: UUID?
    @State private var showingBelowTriggerChangedAlert = false
    @State private var showingMassMessage = false
    @State private var showingFirstStopPrompt = false
    /// Siri's "Notify next client": a text to this stop's client, completing
    /// nothing (NotifyNextAction).
    @State private var textOnlyStop: RouteStop?
    /// The stop that was current when the notify prompt opened. Advancing
    /// completes that stop only; if sync has changed it meanwhile, nothing is
    /// recorded (ActiveRouteStore.CompletionResult.stopChanged).
    @State private var promptStopID: UUID?
    /// The client the notify prompt opened for, pinned so a sync change can't
    /// swap the recipient while the sheet is up.
    @State private var promptNextStop: RouteStop?
    @State private var showingRouteChangedAlert = false
    /// Set while the notify sheet is up; the alert shows once it closes
    /// (iOS won't present an alert over a view that is presenting a sheet).
    @State private var routeChangedAfterSheet = false

    @AppStorage("completedRoutesCount") private var completedRoutesCount = 0

    // Map camera state
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var followDriver = true

    var sortedStops: [RouteStop] { store.sortedStops }
    var currentStopIndex: Int { store.currentStopIndex }
    var currentStop: RouteStop? { store.currentStop }
    var nextStop: RouteStop? { store.nextStop }
    var isLastStop: Bool { store.isLastStop }

    private var nextStopClient: Client? {
        guard let next = nextStop, !next.isCustomStop else { return nil }
        return allClients.first { $0.id == next.clientID }
    }

    private var currentStopClient: Client? {
        currentStop.flatMap(client(for:))
    }

    /// A sheet, dialog or other alert is up on this screen. A new one must be
    /// added here, or Control Center's message can try to show over it.
    private var isPresentingSomething: Bool {
        showingFirstStopPrompt || showingNotifyPrompt || textOnlyStop != nil || recorderStop != nil || showingMassMessage
            || belowTriggerStop != nil || showingBelowTriggerChangedAlert
            || showingRouteRecap || showingNavPicker || showingRouteChangedAlert || showingLocationDeniedAlert
    }

    /// The names of the active services `stop` is expected to need.
    private func expectedServiceNames(for stop: RouteStop) -> [String] {
        let operatorID = route.operatorID
        return ServiceLog.activeServices(allServices, operatorID: operatorID)
            .filter { StopServices.expected(for: stop, client: client(for: stop)).contains($0.id) }
            .map(\.name)
    }

    private func client(for stop: RouteStop) -> Client? {
        guard !stop.isCustomStop else { return nil }
        return allClients.first { $0.id == stop.clientID }
    }

    /// No offer to text the next client: they'd rather not be texted, or this
    /// device can't text (an iPad without Messages, a Mac). The button then
    /// says Complete Stop and moves on.
    private var shouldSkipNextNotify: Bool {
        nextStopClient?.skipNotificationPrompt == true || !MFMessageComposeViewController.canSendText()
    }

    var upcomingStops: [RouteStop] {
        guard currentStopIndex + 1 < sortedStops.count else { return [] }
        return Array(sortedStops[(currentStopIndex + 1)...])
    }

    var body: some View {
        screenWithSheets
        // The job-site areas follow the route by themselves (ActiveRouteStore,
        // SiteMonitor), with or without this screen.
        .onChange(of: store.currentStopID) { _, _ in
            if scenePhase == .active { store.markCurrentStopSeen() }
        }
        // Back in the app with this screen up: whatever stop it shows is seen,
        // and GPS comes back. In the background it's off: arrivals and
        // departures are the job-site areas', which iOS watches by itself
        // with Location set to Always (RouteGPS.needsAlways).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.markCurrentStopSeen() }
            switch RouteGPS.action(for: phase, isMac: OnMac.isMac, status: locationManager.authorizationStatus) {
            case .start: locationManager.startTracking()
            case .stop: locationManager.stopTracking()
            case .none: break
            }
        }
        // Control Center's Complete Stop, when it couldn't complete the stop.
        // Held while something else is up: iOS won't present an alert over a
        // sheet, and shows it once the sheet has closed.
        .alert("Complete Stop", isPresented: Binding(
            get: { RouteSessionManager.shared.completeStopMessage != nil && !isPresentingSomething },
            set: { if !$0 { RouteSessionManager.shared.completeStopMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(RouteSessionManager.shared.completeStopMessage ?? "")
        }
        .onChange(of: locationManager.authorizationStatus) { _, status in
            guard !OnMac.isMac else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if scenePhase != .background { locationManager.startTracking() }
            case .denied, .restricted:
                showingLocationDeniedAlert = true
                Task { await fetchWeatherWithoutGPS() }
            default: break
            }
        }
        .onChange(of: showingRouteRecap) { _, showing in
            guard showing, sortedStops.count >= 5 else { return }
            completedRoutesCount += 1
            if completedRoutesCount >= 2 {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    requestReview()
                }
            }
        }
        .alert("Route Changed", isPresented: $showingRouteChangedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This route was changed on another device, so that stop wasn't marked complete. Check the current stop and try again.")
        }
        .alert("Location Access Required", isPresented: $showingLocationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("End Route", role: .cancel) { store.end() }
        } message: {
            Text("PlowR needs location access to track your route. Enable it in Settings > Privacy > Location Services.")
        }
        .confirmationDialog("Open in Maps", isPresented: $showingNavPicker, titleVisibility: .visible) {
            if let stop = navStop {
                Button("Apple Maps") { openInAppleMaps(stop) }
                if canOpen("comgooglemaps://") {
                    Button("Google Maps") { openInGoogleMaps(stop) }
                }
                if canOpen("waze://") {
                    Button("Waze") { openInWaze(stop) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Location on While Using: GPS works on screen, but job-site arrivals
    /// and departures (and the offer to text the next client) need Always.
    private var alwaysLocationNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Label("Arrival and departure times are recorded only while PlowR is on screen. Set Location to Always to record them with the app closed.",
                  systemImage: "location.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                // The whole 44 pt row is the button, not just the word.
                Text("Settings")
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Open Settings to set Location to Always")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// The route screen with its tracking and sheets. Split from `body`: one
    /// chain of all the screen's modifiers grew too long to type-check.
    private var screenWithSheets: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    progressHeader
                    if OnMac.isMac {
                        // No GPS route-following or texting on a Mac (OnMac).
                        Label("On a Mac, GPS arrival times and texting aren't available. Run routes on your iPhone.",
                              systemImage: "laptopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                    }
                    if RouteGPS.needsAlways(status: locationManager.authorizationStatus, isMac: OnMac.isMac) {
                        alwaysLocationNote
                    }
                    VStack(spacing: PlowRLayout.space3) {
                        routeMap
                        weatherStrip
                        if let stop = currentStop {
                            currentStopCard(stop)
                        } else {
                            routeCompleteCard
                        }
                        if !upcomingStops.isEmpty {
                            upcomingStopsSection
                        }
                    }
                    .padding(.horizontal, PlowRLayout.space4)
                    .padding(.bottom, PlowRLayout.space6)
                }
            }
            .background(PlowRColor.ground)
            .navigationTitle(route.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("End Route") { showingRouteRecap = true }
                        .foregroundStyle(PlowRColor.Status.overdue.text)
                }
            }
        }
        .tint(PlowRColor.brand)
        .onAppear {
            beginTracking()
            // Built with the app in the background (a location relaunch), it
            // hasn't been seen: that waits for the app to come to the front.
            if scenePhase == .active { store.markCurrentStopSeen() }
            openRequestedText()
        }
        .onDisappear {
            // Stops GPS for this screen only. The route itself carries on: only
            // End Route (store.end()) finishes it.
            locationManager.stopTracking()
            // Said about this route: not for the next one.
            RouteSessionManager.shared.completeStopMessage = nil
            RouteSessionManager.shared.textRequest = nil
        }
        // Again when the first fix arrives: the screen opens before it does.
        .task(id: "\(currentStopIndex)-\(locationManager.currentLocation != nil)") {
            etaMinutes = nil
            if let stop = currentStop {
                etaMinutes = await locationManager.calculateETA(to: stop)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, loc in
            guard let loc else { return }
            // GPS weather wins over the stops' (location switched back on).
            if weather == nil || weatherFromStops {
                Task {
                    if let fetched = try? await WeatherService.shared.fetch(
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude
                    ) {
                        weather = fetched
                        weatherFromStops = false
                    }
                }
            }
            if followDriver { recenterMap() }
        }
        .onChange(of: currentStopIndex) { _, _ in
            if followDriver { recenterMap() }
        }
        // No GPS to fetch weather for (a Mac, location off): the stops' own.
        // Keyed by stop only to retry a fetch that failed.
        .task(id: currentStop?.id) { await fetchWeatherWithoutGPS() }
        .onChange(of: SiteMonitor.shared.lastExit) { _, exit in
            guard let exit,
                  let stop = currentStop,
                  stop.id.uuidString == exit.stopID else { return }
            triggerNotifyPrompt()
        }
        // Siri's "Notify next client", once nothing else is up.
        .onChange(of: RouteSessionManager.shared.textRequest) { _, _ in openRequestedText() }
        .onChange(of: isPresentingSomething) { _, _ in openRequestedText() }
        // Each sheet, dialog and alert on this screen is in isPresentingSomething.
        .sheet(item: $textOnlyStop) { stop in
            // A text only: Send, Skip and Cancel complete nothing.
            NotifyPromptView(stop: stop, locationManager: locationManager, onAdvance: {},
                             promptTitle: "Text Current Stop?")
        }
        .sheet(isPresented: $showingFirstStopPrompt) {
            if let first = sortedStops.first {
                NotifyPromptView(
                    stop: first,
                    locationManager: locationManager,
                    onAdvance: {},
                    promptTitle: "Notify First Client?"
                )
            }
        }
        .sheet(isPresented: $showingNotifyPrompt, onDismiss: {
            if routeChangedAfterSheet {
                routeChangedAfterSheet = false
                showingRouteChangedAlert = true
            }
        }) {
            if let next = promptNextStop {
                NotifyPromptView(stop: next, locationManager: locationManager, onAdvance: { advance(completing: promptStopID) })
            }
        }
        .background(
            Color.clear
                .sheet(item: $recorderStop) { stop in
                    StopServiceRecorderView(
                        stop: stop,
                        client: client(for: stop),
                        operatorID: route.operatorID,
                        runID: store.runID,
                        stopStartedAt: stop.id == store.currentStopID ? store.stopStartedAt : store.runStartedAt
                    )
                }
        )
        .sheet(isPresented: $showingMassMessage) {
            MassMessageView(stops: sortedStops, allClients: allClients)
        }
        .proGateSheet($gate)
        .sheet(item: $belowTriggerStop, onDismiss: belowTriggerDismissed) { stop in
            BelowTriggerSheet(clientName: stop.clientName, triggerLabel: belowTrigger(for: stop)?.label ?? "",
                              save: { passBelowTrigger(stop, note: $0, photos: $1) })
        }
        .alert("Route Changed", isPresented: $showingBelowTriggerChangedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This route was changed on another device, so it didn't move on. The below-trigger check was kept. Check the current stop.")
        }
        .sheet(isPresented: $showingRouteRecap) {
            RouteRecapView(
                route: route,
                stops: sortedStops,
                allClients: allClients,
                onEndRoute: { store.end() },
                runID: store.runID,
                runStartedAt: store.runStartedAt
            )
        }
    }

    // MARK: - Progress Header

    /// Where the route stands: a segment per stop (done, current, ahead),
    /// or a bar on a long route, where segments would be slivers.
    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stop \(min(currentStopIndex + 1, sortedStops.count)) of \(sortedStops.count)")
                    .font(PlowRFont.number)
                    .monospacedDigit()
                Spacer()
                Text("\(min(currentStopIndex, sortedStops.count)) done")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
            .foregroundStyle(PlowRColor.ink)
            if sortedStops.count <= 24 {
                HStack(spacing: 3) {
                    ForEach(sortedStops.indices, id: \.self) { index in
                        Capsule()
                            .fill(index < currentStopIndex ? PlowRColor.Status.done.fill
                                  : index == currentStopIndex ? PlowRColor.action : PlowRColor.line)
                            .frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            } else {
                ProgressView(value: Double(currentStopIndex), total: Double(max(sortedStops.count, 1)))
                    .tint(PlowRColor.Status.done.fill)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, PlowRLayout.space4)
        .padding(.vertical, PlowRLayout.space3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Route Map

    private var routeMap: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $mapCameraPosition) {
                // Custom prominent driver annotation
                if let loc = locationManager.currentLocation {
                    Annotation("", coordinate: loc.coordinate, anchor: .center) {
                        driverAnnotationView
                    }
                }

                // Current stop — red with house icon
                if let stop = currentStop, stop.latitude != 0 {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude), anchor: .bottom) {
                        currentStopAnnotationView(name: stop.clientName)
                    }
                }

                // Upcoming stops — numbered orange pins
                ForEach(Array(upcomingStops.prefix(5).enumerated()), id: \.element.id) { idx, stop in
                    if stop.latitude != 0 {
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude), anchor: .bottom) {
                            upcomingStopAnnotationView(number: currentStopIndex + 2 + idx)
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
            // Frame the driver and the stop from the start: MapKit's
            // automatic framing put the stop's pin on the top edge.
            .onAppear { recenterMap() }
            // Only a finger on the map stops following the driver. Telling
            // the app's camera moves apart by their camera changes failed:
            // MapKit can report more than one for a move, and the screen took
            // the extra one for a pan, showing Re-center before anyone had
            // touched the map.
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in followDriver = false })
            .simultaneousGesture(MagnifyGesture().onChanged { _ in followDriver = false })

            // Re-center button appears when user has panned away
            if !followDriver {
                Button {
                    followDriver = true
                    recenterMap()
                } label: {
                    Label("Re-center", systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .padding(10)
            }
        }
    }

    // The driver: forest green, the brand. The pins use the same colors as
    // the rest of the route: copper for where you're going now, outlined
    // green for what's ahead (RouteDetailView's pins follow in its own PR).
    private var driverAnnotationView: some View {
        ZStack {
            Circle()
                .fill(PlowRColor.brand.opacity(0.18))
                .frame(width: 56, height: 56)
            Circle()
                .fill(PlowRColor.brand)
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(PlowRColor.surface, lineWidth: 3))
            Image(systemName: "truck.box.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PlowRColor.onBrand)
        }
        .accessibilityLabel("You")
    }

    private func currentStopAnnotationView(name: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(PlowRColor.action)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(PlowRColor.surface, lineWidth: 3))
                Image(systemName: PlowRSymbol.home.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PlowRColor.onAction)
            }
            Text(name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(PlowRColor.onAction)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PlowRColor.action, in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current stop, \(name)")
    }

    private func upcomingStopAnnotationView(number: Int) -> some View {
        Text("\(number)")
            .font(PlowRFont.label)
            .monospacedDigit()
            .foregroundStyle(PlowRColor.brand)
            .frame(width: 28, height: 28)
            .background(PlowRColor.surface, in: Circle())
            .overlay(Circle().stroke(PlowRColor.brand, lineWidth: 2.5))
            .accessibilityLabel("Stop \(number)")
    }

    // MARK: - Map Camera Logic

    private func recenterMap() {
        mapCameraPosition = computedMapCamera
    }

    private var computedMapCamera: MapCameraPosition {
        let userLoc = locationManager.currentLocation

        // If stop has no geocoded coordinates, center on driver instead
        guard let stop = currentStop, stop.latitude != 0, stop.longitude != 0 else {
            if let loc = userLoc {
                return .camera(MapCamera(centerCoordinate: loc.coordinate, distance: 1000))
            }
            return .userLocation(fallback: .automatic)
        }

        if let userLoc {
            // A region holding both pins, which MapKit fits inside the map
            // whatever its shape: a camera distance is a height, and on this
            // wide, short map it left the stop's pin on the top edge. The
            // margin is room for the stop's pin and name above its point.
            let here = userLoc.coordinate
            let center = CLLocationCoordinate2D(latitude: (here.latitude + stop.latitude) / 2,
                                                longitude: (here.longitude + stop.longitude) / 2)
            let northSouth = CLLocation(latitude: here.latitude, longitude: stop.longitude)
                .distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude))
            let eastWest = CLLocation(latitude: stop.latitude, longitude: here.longitude)
                .distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude))
            return .region(MKCoordinateRegion(
                center: center,
                latitudinalMeters: min(max(northSouth * 1.6 + 300, 300), 15_000),
                longitudinalMeters: min(max(eastWest * 1.3 + 200, 300), 15_000)
            ))
        }
        return .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude),
            distance: 600
        ))
    }

    // MARK: - Weather Strip

    @ViewBuilder
    private var weatherStrip: some View {
        if let w = weather {
            // A card like the stop's, the weather's colour on its icon only:
            // white text on the old coloured strip was faint in dark mode,
            // where the system grey turns light.
            HStack(spacing: PlowRLayout.space2) {
                Image(systemName: w.symbolName)
                    .foregroundStyle(WeatherKind(w.description).iconColor)
                Text("\(Int(w.temperatureF))°F")
                    .font(PlowRFont.number)
                Text("·")
                    .foregroundStyle(PlowRColor.inkSecondary)
                Text(w.description)
                Spacer()
                Text("\(Int(w.windSpeedMph)) mph \(w.windDirectionLabel)")
                    .foregroundStyle(PlowRColor.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(PlowRColor.inkSecondary)
            }
            .font(.subheadline)
            .foregroundStyle(PlowRColor.ink)
            .padding(.horizontal, PlowRLayout.space4)
            .padding(.vertical, PlowRLayout.space3)
            .background(PlowRColor.surface,
                        in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous)
                    .strokeBorder(PlowRColor.line)
            )
            .onTapGesture { openWeather() }
            // WeatherKit's attribution goes wherever its weather shows.
            WeatherAttribution()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Stop Cards

    private func currentStopCard(_ stop: RouteStop) -> some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space4) {
            // Who and where, with the time to get there as big as the name.
            HStack(alignment: .top, spacing: PlowRLayout.space3) {
                VStack(alignment: .leading, spacing: PlowRLayout.space1) {
                    Text("NOW · STOP \(currentStopIndex + 1)")
                        .font(PlowRFont.label)
                        .tracking(0.6)
                        .foregroundStyle(PlowRColor.actionText)
                        .padding(.horizontal, PlowRLayout.space2)
                        .padding(.vertical, 3)
                        .background(PlowRColor.actionSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(stop.clientName)
                        .font(PlowRFont.stopName)
                        .foregroundStyle(PlowRColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !stop.clientAddress.isEmpty {
                        Text(stop.clientAddress)
                            .font(.body)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                    if !stop.clientPhone.isEmpty {
                        Text(stop.clientPhone)
                            .font(.subheadline)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let eta = etaMinutes {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(eta)")
                            .font(PlowRFont.bigNumber)
                            .monospacedDigit()
                            .foregroundStyle(PlowRColor.ink)
                        Text("min away")
                            .font(.footnote)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(eta) minutes away")
                }
            }

            // What this stop is expected to need, and its target time, as set
            // on the stop's page before the route.
            let expected = expectedServiceNames(for: stop)
            let target = RouteFacts.targetMinutes(of: stop, client: client(for: stop))
            if !expected.isEmpty || target > 0 {
                VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                    if !expected.isEmpty {
                        Label(expected.formatted(.list(type: .and)), systemImage: "checklist")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PlowRColor.ink)
                    }
                    if target > 0 {
                        Label("Target \(RouteFacts.duration(target))", systemImage: "timer")
                            .font(.subheadline)
                            .foregroundStyle(PlowRColor.inkSecondary)
                    }
                }
            }

            if !stop.stopNotes.isEmpty || !stop.equipmentNotes.isEmpty {
                VStack(alignment: .leading, spacing: PlowRLayout.space2) {
                    if !stop.stopNotes.isEmpty {
                        Label(stop.stopNotes, systemImage: "note.text")
                            .font(.subheadline)
                            .foregroundStyle(PlowRColor.ink)
                    }
                    if !stop.equipmentNotes.isEmpty {
                        Label(stop.equipmentNotes, systemImage: "wrench.and.screwdriver")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PlowRColor.Status.owed.text)
                    }
                }
                .padding(PlowRLayout.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PlowRColor.raised, in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
            }

            // Getting there, and the record of the work: the quieter choices.
            HStack(spacing: PlowRLayout.space2) {
                Button { openNavigation(for: stop) } label: {
                    Label("Navigate", systemImage: PlowRSymbol.navigate.name)
                }
                .buttonStyle(.plowRSecondary)
                .disabled(stop.latitude == 0 && stop.clientAddress.isEmpty)
                if !stop.isCustomStop {
                    Button { recorderStop = stop } label: {
                        if stop.completedServiceIDs.isEmpty {
                            Label("Record Services", systemImage: "doc.badge.plus")
                        } else {
                            Label("\(stop.completedServiceIDs.count) Recorded", systemImage: PlowRSymbol.complete.name)
                        }
                    }
                    .buttonStyle(.plowRSecondary)
                }
            }

            // A contract with a snow trigger in force today: less may have
            // fallen here than the forecast said.
            if belowTrigger(for: stop) != nil {
                Button {
                    $gate.unless(ProGate.proFeature("Marking below trigger", access)) { belowTriggerStop = stop }
                } label: {
                    Label("Below Trigger", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.plowRSecondary)
            }

            // The one main action, in copper, glove-sized.
            if isLastStop {
                Button {
                    switch store.completeCurrentStop(expecting: stop.id) {
                    case .finishedLastStop, .allStopsAlreadyDone:
                        hapticSuccess()
                        showingRouteRecap = true
                    case .stopChanged:
                        showingRouteChangedAlert = true
                    case .advanced:
                        didAdvance()   // a stop was added after this one elsewhere; it's next
                    case .noActiveRoute:
                        break
                    }
                } label: {
                    Label("Complete Route", systemImage: PlowRSymbol.complete.name)
                }
                .buttonStyle(.plowRAction)
            } else {
                Button { triggerNotifyPrompt() } label: {
                    Label(
                        shouldSkipNextNotify ? "Complete Stop" : "Complete · Text Next Client",
                        systemImage: shouldSkipNextNotify ? PlowRSymbol.complete.name : "arrow.right.circle.fill"
                    )
                }
                .buttonStyle(.plowRAction)
            }
        }
        .padding(PlowRLayout.space4)
        .background(PlowRColor.surface, in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous)
            .stroke(PlowRColor.line, lineWidth: 1))
    }

    private var routeCompleteCard: some View {
        VStack(spacing: PlowRLayout.space4) {
            Image(systemName: PlowRSymbol.complete.name)
                .font(.system(size: 56))
                .foregroundStyle(PlowRColor.Status.done.fill)
                .accessibilityHidden(true)
            Text("All stops complete")
                .font(PlowRFont.title)
                .foregroundStyle(PlowRColor.ink)
            Button { showingRouteRecap = true } label: {
                Text("Review & End Route")
            }
            .buttonStyle(.plowRAction)
        }
        .padding(PlowRLayout.space4)
        .frame(maxWidth: .infinity)
        .background(PlowRColor.surface, in: RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous)
            .stroke(PlowRColor.line, lineWidth: 1))
    }

    private var upcomingStopsSection: some View {
        VStack(alignment: .leading, spacing: PlowRLayout.space2) {
            HStack {
                Text("NEXT UP")
                    .font(PlowRFont.label)
                    .tracking(0.8)
                    .foregroundStyle(PlowRColor.inkSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showingMassMessage = true
                } label: {
                    Label("Message All", systemImage: PlowRSymbol.text.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlowRColor.ink)
                        .padding(.horizontal, PlowRLayout.space3)
                        .frame(minHeight: PlowRLayout.minTapTarget)
                        .background(PlowRColor.raised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(upcomingStops.enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: PlowRLayout.space3) {
                    Text("\(currentStopIndex + 2 + index)")
                        .font(PlowRFont.label)
                        .monospacedDigit()
                        .foregroundStyle(PlowRColor.onBrand)
                        .frame(width: 30, height: 30)
                        .background(PlowRColor.brand, in: Circle())
                        .accessibilityLabel("Stop \(currentStopIndex + 2 + index)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.clientName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PlowRColor.ink)
                        if !stop.clientAddress.isEmpty {
                            Text(stop.clientAddress)
                                .font(.subheadline)
                                .foregroundStyle(PlowRColor.inkSecondary)
                        }
                    }
                    Spacer()
                    Button { openNavigation(for: stop) } label: {
                        Image(systemName: PlowRSymbol.navigate.name)
                            .font(.title2)
                            .foregroundStyle(PlowRColor.brand)
                            .frame(width: PlowRLayout.minTapTarget, height: PlowRLayout.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(stop.latitude == 0 && stop.clientAddress.isEmpty)
                    .accessibilityLabel("Directions to \(stop.clientName)")
                }
                .padding(.vertical, PlowRLayout.space1)
                .padding(.leading, PlowRLayout.space3)
                .padding(.trailing, PlowRLayout.space1)
                .background(PlowRColor.surface, in: RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous)
                    .stroke(PlowRColor.line, lineWidth: 1))
            }
        }
    }

    // MARK: - Navigation

    /// The weather at the stops, where there's no GPS fix to fetch it for.
    /// With GPS it comes with the first fix (onChange of currentLocation).
    /// Fetched once per screen, like the GPS weather: a failed fetch is
    /// tried again at the next stop.
    private func fetchWeatherWithoutGPS() async {
        guard weather == nil,
              RouteWeatherSpot.usesStops(isMac: OnMac.isMac, status: locationManager.authorizationStatus),
              let spot = RouteWeatherSpot.coordinate(
                stops: store.sortedStops.map { (latitude: $0.latitude, longitude: $0.longitude) },
                currentIndex: currentStopIndex),
              let fetched = try? await WeatherService.shared.fetch(latitude: spot.latitude, longitude: spot.longitude),
              weather == nil else { return }
        weather = fetched
        weatherFromStops = true
    }

    private func openWeather() {
        if let url = URL(string: "weather://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://weather.com") {
            UIApplication.shared.open(url)
        }
    }

    /// Whether an app for this URL scheme is installed. The scheme must be in
    /// `LSApplicationQueriesSchemes` (Info.plist), or iOS always answers no.
    private func canOpen(_ scheme: String) -> Bool {
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private func openNavigation(for stop: RouteStop) {
        let hasGoogle = canOpen("comgooglemaps://")
        let hasWaze   = canOpen("waze://")
        if !hasGoogle && !hasWaze {
            openInAppleMaps(stop)
        } else {
            navStop = stop
            showingNavPicker = true
        }
    }

    private func openInAppleMaps(_ stop: RouteStop) {
        if let url = stop.appleMapsDirectionsURL { UIApplication.shared.open(url) }
    }

    private func openInGoogleMaps(_ stop: RouteStop) {
        let urlStr = stop.latitude != 0
            ? "comgooglemaps://?daddr=\(stop.latitude),\(stop.longitude)&directionsmode=driving"
            : "comgooglemaps://?daddr=\(stop.clientAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
    }

    private func openInWaze(_ stop: RouteStop) {
        guard stop.latitude != 0,
              let url = URL(string: "waze://?ll=\(stop.latitude),\(stop.longitude)&navigate=yes") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Haptics

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func hapticSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Route Logic

    /// Starts GPS for the map and ETA (the job-site areas are SiteMonitor's).
    /// Runs every time the screen appears, including after a relaunch restores
    /// the route; only a freshly started route offers to notify its first client.
    private func beginTracking() {
        // A Mac isn't on the route (OnMac): no location asked for or followed.
        if !OnMac.isMac {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestPermission()
            case .authorizedAlways:
                if scenePhase != .background { locationManager.startTracking() }
            case .authorizedWhenInUse:
                if scenePhase != .background { locationManager.startTracking() }
                // Arrivals and departures need Always (RouteGPS.needsAlways):
                // iOS offers the change once; the screen says so after that.
                if scenePhase != .background { locationManager.requestAlways() }
            case .denied, .restricted:
                showingLocationDeniedAlert = true
            @unknown default:
                locationManager.requestPermission()
            }
        }
        guard store.isFirstStopPromptPending else { return }
        store.isFirstStopPromptPending = false
        hapticSuccess()
        // Prompt to notify the first client before driving to them
        if MFMessageComposeViewController.canSendText(),
           let firstStop = sortedStops.first,
           !firstStop.clientPhone.isEmpty,
           !(allClients.first { $0.id == firstStop.clientID }?.skipNotificationPrompt ?? false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingFirstStopPrompt = true
            }
        }
    }

    private func triggerNotifyPrompt() {
        // Nothing to notify on the last stop or once every stop is done (it
        // used to open an empty sheet then).
        guard nextStop != nil, !showingNotifyPrompt else { return }
        if shouldSkipNextNotify {
            advance(completing: currentStop?.id)
            return
        }
        openNotifyPrompt()
    }

    /// Opens the text Siri asked for, when nothing else is up, if it's still
    /// wanted (NotifyNextAction.stopToOpen). Asked again while that text is
    /// already open, it's dropped rather than reopened after it's sent.
    private func openRequestedText() {
        guard let request = RouteSessionManager.shared.textRequest else { return }
        if request.stopID == textOnlyStop?.id {
            RouteSessionManager.shared.textRequest = nil
            return
        }
        guard !isPresentingSomething else { return }
        RouteSessionManager.shared.textRequest = nil
        textOnlyStop = NotifyNextAction.stopToOpen(request, in: store)
    }

    /// After Below Trigger moved on: the client now current is offered the
    /// "on my way" text, as after Done (unless they'd rather not be texted).
    /// It names no stop to complete (`promptStopID` nil), so its Send or
    /// Skip completes nothing, even if iCloud brings the passed stop back.
    /// Returns whether it was offered.
    private func offerHeadsUp(after passedID: UUID) -> Bool {
        guard MFMessageComposeViewController.canSendText(),
              let next = currentStop, !showingNotifyPrompt, store.isBehindCurrentStop(passedID),
              client(for: next)?.skipNotificationPrompt != true else { return false }
        promptStopID = nil
        promptNextStop = next
        haptic(.light)
        showingNotifyPrompt = true
        return true
    }

    /// The Complete button and leaving a stop's geofence land here.
    private func openNotifyPrompt() {
        guard let next = nextStop, !showingNotifyPrompt else { return }
        promptStopID = currentStop?.id
        promptNextStop = next
        haptic(.light)
        showingNotifyPrompt = true
    }

    /// `stopID`: the stop to complete; nil for the heads-up after Below
    /// Trigger, which completes nothing (NotifyAdvance).
    private func advance(completing stopID: UUID?) {
        if NotifyAdvance.run(completing: stopID, store: store) == .stopChanged {
            if showingNotifyPrompt { routeChangedAfterSheet = true } else { showingRouteChangedAlert = true }
            return
        }
        didAdvance()
    }

    /// The contract trigger Below Trigger offers at `stop` today, unless
    /// Record Services already saved work there this run: that record (and
    /// any invoice) would stand beside a "not cleared" check.
    private func belowTrigger(for stop: RouteStop) -> StormWatch.Trigger? {
        guard let client = client(for: stop), stop.completedServiceIDs.isEmpty else { return nil }
        if let run = store.runID,
           ServiceLog.existingRecordForStop(stop, of: client, run: run,
                                            startedAt: store.stopStartedAt ?? store.runStartedAt ?? .now,
                                            in: modelContext) != nil { return nil }
        return TriggerChecks.trigger(for: stop, client: client, on: store.runStartedAt ?? .now,
                                     contracts: allContracts, services: allServices)
    }

    /// Below Trigger, saved (TriggerChecks.passBelowTrigger). What follows
    /// waits for the sheet to close.
    private func passBelowTrigger(_ stop: RouteStop, note: String, photos: [CapturedPhoto]) {
        guard let client = client(for: stop) else { return }
        belowTriggerPassedID = stop.id
        belowTriggerOutcome = TriggerChecks.passBelowTrigger(stop, of: client, store: store, routeName: route.name,
                                                             operatorID: route.operatorID, note: note,
                                                             photos: photos, in: modelContext)
    }

    private func belowTriggerDismissed() {
        defer {
            belowTriggerOutcome = nil
            belowTriggerPassedID = nil
        }
        switch belowTriggerOutcome {
        case .movedOn:
            // The prompt's own advance plays the haptic; without it, play it here.
            if let passed = belowTriggerPassedID, offerHeadsUp(after: passed) { break }
            didAdvance()
        case .finishedRoute:
            hapticSuccess()
            showingRouteRecap = true
        case .routeChanged: showingBelowTriggerChangedAlert = true
        case .alreadyPast, nil: break
        }
    }

    /// After this screen moved the store to the next stop. The new stop's
    /// geofence follows the store (`onChange(of: store.currentStopID)`), so it
    /// also moves when Siri or Control Center completes a stop.
    private func didAdvance() {
        haptic()
    }
}
