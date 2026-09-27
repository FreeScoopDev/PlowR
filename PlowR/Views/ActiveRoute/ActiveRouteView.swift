import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import StoreKit

/// The in-progress route screen. It shows and drives `ActiveRouteStore`, which
/// owns the route: this view can appear, disappear or be torn down with the app
/// without starting, ending or losing the route.
struct ActiveRouteView: View {
    let route: PlowRoute
    @Environment(ActiveRouteStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview

    @Query private var allClients: [Client]

    @State private var locationManager = LocationManager()
    @State private var showingNotifyPrompt = false
    @State private var showingEndConfirmation = false
    @State private var showingRouteRecap = false
    @State private var showingLocationDeniedAlert = false

    @State private var weather: WeatherCondition? = nil
    @State private var etaMinutes: Int? = nil
    @State private var showingNavPicker = false
    @State private var navStop: RouteStop? = nil
    @State private var showingServiceRecorder = false
    @State private var showingMassMessage = false
    @State private var showingFirstStopPrompt = false
    /// The stop that was current when the notify prompt opened. Advancing
    /// completes that stop only; if sync has changed it meanwhile, nothing is
    /// recorded (ActiveRouteStore.CompletionResult.stopChanged).
    @State private var promptStopID: UUID?
    /// The client the notify prompt opened for, pinned so a sync change can't
    /// swap the recipient while the sheet is up.
    @State private var promptNextStop: RouteStop?
    @State private var showingRouteChangedAlert = false

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
        guard let stop = currentStop, !stop.isCustomStop else { return nil }
        return allClients.first { $0.id == stop.clientID }
    }

    private var shouldSkipNextNotify: Bool {
        nextStopClient?.skipNotificationPrompt == true
    }

    var upcomingStops: [RouteStop] {
        guard currentStopIndex + 1 < sortedStops.count else { return [] }
        return Array(sortedStops[(currentStopIndex + 1)...])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    progressHeader
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
            RouteSessionManager.shared.isRouteActive = true
            RouteSessionManager.shared.onCompleteStop = { triggerNotifyPrompt() }
            RouteSessionManager.shared.onNotifyNext = { openNotifyPrompt() }
        }
        .onDisappear {
            // Stops GPS for this screen only. The route itself carries on: only
            // End Route (store.end()) finishes it.
            locationManager.stopTracking()
            RouteSessionManager.shared.isRouteActive = false
            RouteSessionManager.shared.onCompleteStop = nil
            RouteSessionManager.shared.onNotifyNext = nil
        }
        .task(id: currentStopIndex) {
            etaMinutes = nil
            if let stop = currentStop {
                etaMinutes = await locationManager.calculateETA(to: stop)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, loc in
            guard let loc else { return }
            if weather == nil {
                Task {
                    weather = try? await WeatherService.shared.fetch(
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude
                    )
                }
            }
            if followDriver { recenterMap() }
        }
        .onChange(of: currentStopIndex) { _, _ in
            if followDriver { recenterMap() }
        }
        .onChange(of: locationManager.lastExitedRegionID) { _, regionID in
            guard let regionID,
                  let stop = currentStop,
                  stop.id.uuidString == regionID else { return }
            locationManager.lastExitedRegionID = nil
            triggerNotifyPrompt()
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
        .sheet(isPresented: $showingNotifyPrompt) {
            if let next = promptNextStop {
                NotifyPromptView(stop: next, locationManager: locationManager, onAdvance: { advance(completing: promptStopID) })
            }
        }
        .background(
            Color.clear
                .sheet(isPresented: $showingServiceRecorder) {
                    if let stop = currentStop {
                        StopServiceRecorderView(
                            stop: stop,
                            client: currentStopClient,
                            operatorID: route.operatorID
                        )
                    }
                }
        )
        .sheet(isPresented: $showingMassMessage) {
            MassMessageView(stops: sortedStops, allClients: allClients)
        }
        .sheet(isPresented: $showingRouteRecap) {
            RouteRecapView(
                route: route,
                stops: sortedStops,
                allClients: allClients,
                onEndRoute: { store.end() }
            )
        }
        .onChange(of: locationManager.authorizationStatus) { _, status in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.startTracking()
                if let stop = currentStop { locationManager.startMonitoringStop(stop) }
            case .denied, .restricted:
                showingLocationDeniedAlert = true
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
                if UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
                    Button("Google Maps") { openInGoogleMaps(stop) }
                }
                if UIApplication.shared.canOpenURL(URL(string: "waze://")!) {
                    Button("Waze") { openInWaze(stop) }
                }
                Button("Cancel", role: .cancel) {}
            }
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
            .background(weatherBackground(w))
            .onTapGesture { openWeather() }
        }
    }

    private func weatherBackground(_ w: WeatherCondition) -> Color {
        let d = w.description
        if d.contains("Snow") || d.contains("Blizzard") { return .blue }
        if d.contains("Thunder") { return .purple }
        if d.contains("Rain") || d.contains("Shower") || d.contains("Drizzle") { return .indigo }
        if d.contains("Fog") { return Color(white: 0.4) }
        if d.contains("Clear") { return .teal }
        return Color(.systemGray)
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !stop.isCustomStop {
                Button {
                    showingServiceRecorder = true
                } label: {
                    HStack {
                        Label("Record Services for Invoice", systemImage: "doc.badge.plus")
                            .font(.subheadline)
                        Spacer()
                        if !stop.completedServiceIDs.isEmpty {
                            Text("\(stop.completedServiceIDs.count) recorded")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    case .advanced, .noActiveRoute:
                        break   // a stop was added after this one; its card shows next
                    }
                } label: {
                    Label("Complete Route", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Button { triggerNotifyPrompt() } label: {
                    Label(
                        shouldSkipNextNotify ? "Mark Stop Complete" : "Done — Notify Next Client",
                        systemImage: shouldSkipNextNotify ? "checkmark.circle.fill" : "arrow.right.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                    Text("\(currentStopIndex + 2 + index)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Navigation

    private func openWeather() {
        if let url = URL(string: "weather://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://weather.com") {
            UIApplication.shared.open(url)
        }
    }

    private func openNavigation(for stop: RouteStop) {
        let hasGoogle = UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
        let hasWaze   = UIApplication.shared.canOpenURL(URL(string: "waze://")!)
        if !hasGoogle && !hasWaze {
            openInAppleMaps(stop)
        } else {
            navStop = stop
            showingNavPicker = true
        }
    }

    private func openInAppleMaps(_ stop: RouteStop) {
        let addr = stop.clientAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = stop.latitude != 0
            ? "maps://?daddr=\(stop.latitude),\(stop.longitude)&dirflg=d"
            : "maps://?daddr=\(addr)"
        if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
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

    /// Starts GPS and geofencing for the current stop. Runs every time the
    /// screen appears, including after a relaunch restores the route; only a
    /// freshly started route offers to notify its first client.
    private func beginTracking() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestPermission()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startTracking()
            if let stop = currentStop { locationManager.startMonitoringStop(stop) }
        case .denied, .restricted:
            showingLocationDeniedAlert = true
        @unknown default:
            locationManager.requestPermission()
        }
        guard store.isFirstStopPromptPending else { return }
        store.isFirstStopPromptPending = false
        hapticSuccess()
        // Prompt to notify the first client before driving to them
        if let firstStop = sortedStops.first,
           !firstStop.clientPhone.isEmpty,
           !(allClients.first { $0.id == firstStop.clientID }?.skipNotificationPrompt ?? false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingFirstStopPrompt = true
            }
        }
    }

    private func triggerNotifyPrompt() {
        // Nothing to notify on the last stop or once every stop is done (Siri
        // can still call this then; it used to open an empty sheet).
        guard nextStop != nil, !showingNotifyPrompt else { return }
        if shouldSkipNextNotify {
            advance(completing: currentStop?.id)
            return
        }
        openNotifyPrompt()
    }

    /// Siri's "Notify next client" and the Complete button both land here.
    private func openNotifyPrompt() {
        guard let next = nextStop, !showingNotifyPrompt else { return }
        promptStopID = currentStop?.id
        promptNextStop = next
        haptic(.light)
        showingNotifyPrompt = true
    }

    private func advance(completing stopID: UUID?) {
        guard let stopID else { return }
        if store.completeCurrentStop(expecting: stopID) == .stopChanged {
            showingRouteChangedAlert = true
            return
        }
        haptic()
        locationManager.clearAllGeofences()
        if let stop = currentStop { locationManager.startMonitoringStop(stop) }
    }
}
