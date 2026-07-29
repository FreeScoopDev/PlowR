import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import ActivityKit

struct ActiveRouteView: View {
    let route: PlowRoute
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allClients: [Client]

    @State private var locationManager = LocationManager()
    @State private var currentStopIndex = 0
    @State private var showingNotifyPrompt = false
    @State private var showingEndConfirmation = false
    @State private var showingLocationDeniedAlert = false
    @State private var liveActivity: Activity<PlowRRouteAttributes>?

    @State private var weather: WeatherCondition? = nil
    @State private var etaMinutes: Int? = nil
    @State private var showingNavPicker = false
    @State private var navStop: RouteStop? = nil
    @State private var currentStopStartTime: Date? = nil
    @State private var showingServiceRecorder = false

    // Map camera state
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var followDriver = true
    @State private var isSettingCamera = false

    var sortedStops: [RouteStop] { route.sortedStops }

    var currentStop: RouteStop? {
        guard currentStopIndex < sortedStops.count else { return nil }
        return sortedStops[currentStopIndex]
    }

    var nextStop: RouteStop? {
        guard currentStopIndex + 1 < sortedStops.count else { return nil }
        return sortedStops[currentStopIndex + 1]
    }

    var isLastStop: Bool { currentStopIndex >= sortedStops.count - 1 }

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
                    Button("End Route") { showingEndConfirmation = true }
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear { startRoute() }
        .onDisappear {
            locationManager.stopTracking()
            endLiveActivity()
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
        .sheet(isPresented: $showingNotifyPrompt) {
            if let next = nextStop {
                NotifyPromptView(stop: next, locationManager: locationManager, onAdvance: advanceToNextStop)
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
        .alert("Location Access Required", isPresented: $showingLocationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("PlowR needs location access to track your route. Enable it in Settings > Privacy > Location Services.")
        }
        .confirmationDialog("End Route?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End Route", role: .destructive) {
                endLiveActivity()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will stop GPS tracking and end your current route.")
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
        guard let stop = currentStop, stop.latitude != 0 else { return .automatic }
        if let userLoc = locationManager.currentLocation {
            let stopLoc = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
            let dist = userLoc.distance(from: stopLoc)
            // Zoom tighter when close, wider when far; bias slightly toward driver
            let cameraDistance = max(250, min(dist * 1.6, 12_000))
            // Weight center 60% toward driver, 40% toward stop
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
                    recordStopStats(for: currentStop)
                    endLiveActivity()
                    dismiss()
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
                endLiveActivity()
                dismiss()
            } label: {
                Text("End Route")
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
            Text("Up Next")
                .font(.headline)
                .foregroundStyle(.secondary)
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

    // MARK: - Route Logic

    private func startRoute() {
        currentStopStartTime = Date()
        startLiveActivity()
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
    }

    private func triggerNotifyPrompt() {
        guard !isLastStop, !showingNotifyPrompt else { return }
        if shouldSkipNextNotify {
            advanceToNextStop()
            return
        }
        showingNotifyPrompt = true
    }

    private func advanceToNextStop() {
        recordStopStats(for: currentStop)
        currentStopIndex += 1
        currentStopStartTime = Date()
        locationManager.clearAllGeofences()
        if let stop = currentStop { locationManager.startMonitoringStop(stop) }
        updateLiveActivity()
    }

    private func recordStopStats(for stop: RouteStop?) {
        guard let stop, !stop.isCustomStop,
              let startTime = currentStopStartTime else { return }
        let minutes = Date().timeIntervalSince(startTime) / 60.0
        let clientID = stop.clientID
        // Fetch all clients and match by UUID — avoids #Predicate conflict with SwiftData's internal id
        if let client = try? modelContext.fetch(FetchDescriptor<Client>()).first(where: { $0.id == clientID }) {
            client.totalVisits += 1
            client.totalServiceMinutes += max(0, minutes)
            client.lastServiceDate = Date()
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = PlowRRouteAttributes(routeID: route.id.uuidString, routeName: route.name)
        let state = PlowRRouteAttributes.ContentState(
            currentStopName: currentStop?.clientName ?? "",
            currentStopAddress: currentStop?.clientAddress ?? "",
            currentStopNumber: 1,
            totalStops: sortedStops.count,
            routeName: route.name
        )
        liveActivity = try? Activity<PlowRRouteAttributes>.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
    }

    private func updateLiveActivity() {
        guard let activity = liveActivity else { return }
        let state = PlowRRouteAttributes.ContentState(
            currentStopName: currentStop?.clientName ?? "Done",
            currentStopAddress: currentStop?.clientAddress ?? "",
            currentStopNumber: currentStopIndex + 1,
            totalStops: sortedStops.count,
            routeName: route.name
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        let state = PlowRRouteAttributes.ContentState(
            currentStopName: "Route Complete",
            currentStopAddress: "",
            currentStopNumber: sortedStops.count,
            totalStops: sortedStops.count,
            routeName: route.name
        )
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 30)) }
        liveActivity = nil
    }
}
