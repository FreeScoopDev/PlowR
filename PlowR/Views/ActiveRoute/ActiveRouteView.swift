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
    @State private var isSettingCamera = false

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
    /// says Mark Stop Complete and moves on.
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
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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
                    routeMap
                    weatherStrip
                    VStack(spacing: 12) {
                        if let stop = currentStop {
                            currentStopCard(stop)
                        } else {
                            routeCompleteCard
                        }
                        if !upcomingStops.isEmpty {
                            upcomingStopsSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(route.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("End Route") { showingRouteRecap = true }
                        .foregroundStyle(.red)
                }
            }
        }
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

    private var progressHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stop \(min(currentStopIndex + 1, sortedStops.count)) of \(sortedStops.count)")
                    .font(.headline)
                if let eta = etaMinutes {
                    Text("ETA \(eta) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ProgressView(value: Double(currentStopIndex), total: Double(max(sortedStops.count, 1)))
                .frame(width: 120)
                .tint(.blue)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
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
            .frame(height: 260)
            .onMapCameraChange(frequency: .onEnd) { _ in
                if isSettingCamera {
                    isSettingCamera = false
                } else {
                    followDriver = false
                }
            }

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

    // Pulsing blue truck — unmistakably the driver
    private var driverAnnotationView: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.18))
                .frame(width: 58, height: 58)
            Circle()
                .stroke(Color.blue.opacity(0.35), lineWidth: 2)
                .frame(width: 58, height: 58)
            Circle()
                .fill(Color.blue)
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
            Image(systemName: "truck.box.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func currentStopAnnotationView(name: String) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Image(systemName: "house.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.red)
                .clipShape(Capsule())
        }
    }

    private func upcomingStopAnnotationView(number: Int) -> some View {
        ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Map Camera Logic

    private func recenterMap() {
        let newPosition = computedMapCamera
        isSettingCamera = true
        mapCameraPosition = newPosition
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
            let stopLoc = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
            let dist = userLoc.distance(from: stopLoc)
            let cameraDistance = max(250, min(dist * 1.6, 12_000))
            let midLat = userLoc.coordinate.latitude * 0.6 + stop.latitude * 0.4
            let midLon = userLoc.coordinate.longitude * 0.6 + stop.longitude * 0.4
            return .camera(MapCamera(
                centerCoordinate: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                distance: cameraDistance
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
            HStack(spacing: 8) {
                Image(systemName: w.symbolName)
                Text("\(Int(w.temperatureF))°F")
                    .fontWeight(.semibold)
                Text("·")
                Text(w.description)
                Spacer()
                Text("\(Int(w.windSpeedMph)) mph \(w.windDirectionLabel)")
                    .foregroundStyle(.white.opacity(0.75))
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(WeatherKind(w.description).background)
            .onTapGesture { openWeather() }
            // WeatherKit's attribution goes wherever its weather shows.
            WeatherAttribution()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
        }
    }

    // MARK: - Stop Cards

    private func currentStopCard(_ stop: RouteStop) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Current Stop", systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .clipShape(Capsule())
                Spacer()
                Button { openNavigation(for: stop) } label: {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(stop.latitude == 0 && stop.clientAddress.isEmpty)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.clientName)
                    .font(.title2.weight(.bold))
                if !stop.clientAddress.isEmpty {
                    Text(stop.clientAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !stop.clientPhone.isEmpty {
                    Text(stop.clientPhone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // What this stop is expected to need, and its target time, as set
            // on the stop's page before the route.
            let expected = expectedServiceNames(for: stop)
            let target = RouteFacts.targetMinutes(of: stop, client: client(for: stop))
            if !expected.isEmpty || target > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    if !expected.isEmpty {
                        Label(expected.formatted(.list(type: .and)), systemImage: "checklist")
                            .font(.caption.weight(.medium))
                    }
                    if target > 0 {
                        Label("Target \(RouteFacts.duration(target))", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            if !stop.stopNotes.isEmpty || !stop.equipmentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !stop.stopNotes.isEmpty {
                        Label(stop.stopNotes, systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !stop.equipmentNotes.isEmpty {
                        Label(stop.equipmentNotes, systemImage: "wrench.and.screwdriver")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerSmall, style: .continuous))
            }

            if !stop.isCustomStop {
                Button {
                    recorderStop = stop
                } label: {
                    HStack {
                        Label("Record Services", systemImage: "doc.badge.plus")
                            .font(.subheadline)
                        Spacer()
                        if !stop.completedServiceIDs.isEmpty {
                            StatusChip("\(stop.completedServiceIDs.count) recorded", color: .green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // A contract with a snow trigger in force today: less may have
            // fallen here than the forecast said.
            if belowTrigger(for: stop) != nil {
                Button {
                    $gate.unless(ProGate.proFeature("Marking below trigger", access)) { belowTriggerStop = stop }
                } label: {
                    Label("Below Trigger", systemImage: "arrow.down.circle")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
                }
                .buttonStyle(.plain)
            }

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
                    Label("Complete Route", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .primaryActionStyle(.green)
            } else {
                Button { triggerNotifyPrompt() } label: {
                    Label(
                        shouldSkipNextNotify ? "Mark Stop Complete" : "Done — Notify Next Client",
                        systemImage: shouldSkipNextNotify ? "checkmark.circle.fill" : "arrow.right.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .primaryActionStyle(.blue)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
    }

    private var routeCompleteCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("All stops complete!")
                .font(.title2.weight(.bold))
            Button {
                showingRouteRecap = true
            } label: {
                Text("Review & End Route")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
    }

    private var upcomingStopsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingMassMessage = true
                } label: {
                    Label("Message All", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(upcomingStops.enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: 12) {
                    StopNumberBadge(number: currentStopIndex + 2 + index)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.clientName).font(.subheadline.weight(.medium))
                        if !stop.clientAddress.isEmpty {
                            Text(stop.clientAddress).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button { openNavigation(for: stop) } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(stop.latitude == 0 && stop.clientAddress.isEmpty)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
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
