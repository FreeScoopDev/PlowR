import SwiftUI
import MapKit
import SwiftData
import CoreLocation

struct PropertyScannerView: View {
    let client: Client
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition
    @State private var addressConfirmed = false
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showingLookAround = false
    @State private var isLoadingLookAround = false
    @State private var showingLocationAdjust = false
    @State private var isDrawing = false
    @State private var currentPoints: [CLLocationCoordinate2D] = []
    @State private var zones: [ZoneDraft] = []
    @State private var showingLabelEntry = false
    @State private var pendingLabel = ""
    @State private var editingZoneIndex: Int? = nil
    @State private var selectedVertexIndex: Int? = nil
    @State private var isSaving = false
    @State private var zoneColors: [Color] = [.blue, .green, .orange, .purple, .yellow]

    struct ZoneDraft: Identifiable {
        let id = UUID()
        var label: String
        var coordinates: [CLLocationCoordinate2D]
        var areaSquareFeet: Double
        var rateType: String = "perSqFt"
        var elevationGrade: Double = 0.0
        var hasElevationData: Bool = false

        var terrainLabel: String {
            guard hasElevationData else { return "" }
            switch elevationGrade {
            case ..<2:   return "Flat"
            case 2..<8:  return "Moderate slope"
            default:     return "Steep"
            }
        }

        var terrainColor: Color {
            switch elevationGrade {
            case ..<2:  return .green
            case 2..<8: return .yellow
            default:    return .red
            }
        }
    }

    init(client: Client) {
        self.client = client
        let center = CLLocationCoordinate2D(latitude: client.latitude, longitude: client.longitude)
        _cameraPosition = State(initialValue: .camera(
            MapCamera(centerCoordinate: center, distance: 120, heading: 0, pitch: 0)
        ))
        _zones = State(initialValue: client.sortedZones.map { zone in
            ZoneDraft(
                label: zone.label,
                coordinates: zone.coordinates,
                areaSquareFeet: zone.areaSquareFeet,
                rateType: zone.rateType,
                elevationGrade: zone.elevationGrade,
                hasElevationData: true
            )
        })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer

                VStack(spacing: 0) {
                    if !addressConfirmed {
                        addressConfirmationBanner
                    } else if isDrawing {
                        drawingInstructionsBanner
                    } else if editingZoneIndex != nil {
                        editModeBanner
                    }
                    Spacer()
                    controlPanel
                }
            }
            .navigationTitle("Map Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if addressConfirmed && !isDrawing && editingZoneIndex == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Button("Save") { saveZones() }
                                .disabled(zones.isEmpty)
                        }
                    }
                }
                if editingZoneIndex != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done Editing") {
                            editingZoneIndex = nil
                            selectedVertexIndex = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingLabelEntry) {
                ZoneLabelSheet(
                    suggestedLabel: suggestedLabel,
                    pendingLabel: $pendingLabel
                ) { confirmed in
                    if confirmed, !currentPoints.isEmpty {
                        let area = currentPoints.enclosedAreaInSquareFeet()
                        zones.append(ZoneDraft(label: pendingLabel, coordinates: currentPoints, areaSquareFeet: area))
                    }
                    currentPoints = []
                    isDrawing = false
                    pendingLabel = ""
                }
            }
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Completed zones
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    if zone.coordinates.count >= 3 {
                        let isEditing = editingZoneIndex == index
                        MapPolygon(coordinates: zone.coordinates)
                            .foregroundStyle(zoneColor(index).opacity(isEditing ? 0.4 : zoneFillOpacity(zone)))
                            .stroke(isEditing ? Color.white : zoneColor(index), lineWidth: isEditing ? 3 : 2)
                    }
                }
                // Zone centroid labels (hidden while editing that zone)
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    if zone.coordinates.count >= 3, editingZoneIndex != index {
                        let center = zoneCentroid(zone.coordinates)
                        Annotation("", coordinate: center) {
                            VStack(spacing: 2) {
                                Text(zone.label)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(zoneColor(index).opacity(0.85))
                                    .clipShape(Capsule())
                                if zone.hasElevationData && zone.elevationGrade >= 2 {
                                    Text(zone.terrainLabel)
                                        .font(.system(size: 8))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(zone.terrainColor.opacity(0.8))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                // Vertex edit handles
                if let editIdx = editingZoneIndex, editIdx < zones.count {
                    ForEach(Array(zones[editIdx].coordinates.enumerated()), id: \.offset) { vertIdx, coord in
                        Annotation("", coordinate: coord) {
                            Circle()
                                .fill(selectedVertexIndex == vertIdx ? Color.yellow : Color.white)
                                .stroke(Color.blue, lineWidth: 2)
                                .frame(width: 20, height: 20)
                                .shadow(radius: 2)
                        }
                    }
                }
                // In-progress polyline
                if currentPoints.count >= 2 {
                    MapPolyline(coordinates: currentPoints)
                        .stroke(.yellow, lineWidth: 2)
                }
                // In-progress tap points
                ForEach(Array(currentPoints.enumerated()), id: \.offset) { index, coord in
                    Annotation("\(index + 1)", coordinate: coord) {
                        Circle()
                            .fill(index == 0 ? Color.green : Color.yellow)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Text(index == 0 ? "●" : "\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.black)
                            }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .onTapGesture { position in
                guard addressConfirmed else { return }
                guard let coord = proxy.convert(position, from: .local) else { return }

                if isDrawing {
                    handleDrawingTap(coord)
                } else if let editIdx = editingZoneIndex {
                    handleVertexEditTap(coord, zoneIndex: editIdx)
                } else {
                    handleZoneSelectTap(coord)
                }
            }
            .mapControls {
                MapScaleView()
                MapCompass()
                MapPitchToggle()
            }
            .lookAroundViewer(isPresented: $showingLookAround, initialScene: lookAroundScene)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Tap Handlers

    private func handleDrawingTap(_ coord: CLLocationCoordinate2D) {
        if currentPoints.count >= 3,
           let first = currentPoints.first,
           approxDistanceMeters(coord, first) < 2 {
            showingLabelEntry = true
        } else {
            currentPoints.append(coord)
        }
    }

    private func handleVertexEditTap(_ coord: CLLocationCoordinate2D, zoneIndex: Int) {
        if let selVertex = selectedVertexIndex {
            // Drop selected vertex at new location
            zones[zoneIndex].coordinates[selVertex] = coord
            zones[zoneIndex].areaSquareFeet = zones[zoneIndex].coordinates.enclosedAreaInSquareFeet()
            selectedVertexIndex = nil
        } else {
            // Try to pick up a vertex within 4 m
            for (i, vertex) in zones[zoneIndex].coordinates.enumerated() {
                if approxDistanceMeters(coord, vertex) < 4 {
                    selectedVertexIndex = i
                    return
                }
            }
            // Tap outside any vertex → exit edit mode
            editingZoneIndex = nil
        }
    }

    private func handleZoneSelectTap(_ coord: CLLocationCoordinate2D) {
        // Tap inside a zone polygon → enter vertex edit mode (check in reverse so top zone wins)
        for i in stride(from: zones.count - 1, through: 0, by: -1) {
            if zones[i].coordinates.count >= 3,
               pointInPolygon(coord, polygon: zones[i].coordinates) {
                editingZoneIndex = i
                selectedVertexIndex = nil
                return
            }
        }
    }

    // MARK: - Overlays

    private var addressConfirmationBanner: some View {
        VStack(spacing: 12) {
            Text("Is this the correct property?")
                .font(.headline)
            Text(client.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Wrong Address") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    showingLocationAdjust = true
                } label: {
                    Label("Move Pin", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(.bordered)
                .disabled(client.latitude == 0)
                Button {
                    loadLookAround()
                } label: {
                    if isLoadingLookAround {
                        ProgressView().scaleEffect(0.8).frame(width: 44)
                    } else {
                        Label("Street View", systemImage: "binoculars")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingLookAround || client.latitude == 0)
                Button("Correct") { addressConfirmed = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
        .sheet(isPresented: $showingLocationAdjust) {
            NavigationStack {
                LocationAdjustView(client: client) { coord, address in
                    // Update the map camera to the corrected location
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: coord,
                        distance: 80
                    ))
                    // Persist coordinate + address immediately
                    client.latitude = coord.latitude
                    client.longitude = coord.longitude
                    if !address.isEmpty { client.address = address }
                }
            }
        }
    }

    private func loadLookAround() {
        isLoadingLookAround = true
        Task {
            let coord = CLLocationCoordinate2D(latitude: client.latitude, longitude: client.longitude)
            let request = MKLookAroundSceneRequest(coordinate: coord)
            lookAroundScene = try? await request.scene
            isLoadingLookAround = false
            if lookAroundScene != nil { showingLookAround = true }
        }
    }

    private var drawingInstructionsBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "hand.tap.fill")
                Text("Tap the map to outline this zone")
                    .font(.subheadline)
                Spacer()
                if !currentPoints.isEmpty {
                    Button("Undo") { currentPoints.removeLast() }
                        .font(.subheadline)
                }
            }
            if currentPoints.count >= 3 {
                let area = Int(currentPoints.enclosedAreaInSquareFeet())
                let nearClose = approxDistanceMeters(currentPoints.last ?? currentPoints[0], currentPoints[0]) < 6
                HStack(spacing: 8) {
                    Text("\(area) sq ft")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if nearClose {
                        Text("· tap first point to close")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var editModeBanner: some View {
        HStack {
            Image(systemName: selectedVertexIndex != nil ? "smallcircle.filled.circle" : "hand.tap")
            Text(selectedVertexIndex != nil
                 ? "Tap new location to move corner"
                 : "Tap a corner handle to select it")
                .font(.subheadline)
            Spacer()
            if selectedVertexIndex != nil {
                Button("Cancel") { selectedVertexIndex = nil }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 0) {
            if !zones.isEmpty {
                zoneList
                Divider()
            }
            actionBar
        }
        .background(.regularMaterial)
    }

    private var zoneList: some View {
        VStack(spacing: 0) {
            ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                HStack(spacing: 12) {
                    Circle()
                        .fill(zoneColor(index))
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(zone.label)
                            .font(.subheadline).bold()
                        HStack(spacing: 6) {
                            Text("\(Int(zone.areaSquareFeet)) sq ft")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !zone.terrainLabel.isEmpty {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(zone.terrainColor)
                                        .frame(width: 6, height: 6)
                                    Text(zone.terrainLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { zone.rateType },
                        set: { zones[index].rateType = $0 }
                    )) {
                        Text("$/sqft").tag("perSqFt")
                        Text("Flat").tag("flat")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                    Button {
                        zones.remove(at: index)
                        if editingZoneIndex == index { editingZoneIndex = nil }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(editingZoneIndex == index ? Color.blue.opacity(0.08) : Color.clear)
                Divider().padding(.leading)
            }
        }
        .frame(maxHeight: 220)
    }

    private var actionBar: some View {
        HStack {
            if isDrawing {
                Button("Cancel Drawing") {
                    currentPoints = []
                    isDrawing = false
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button("Close Zone") {
                    guard currentPoints.count >= 3 else { return }
                    showingLabelEntry = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentPoints.count < 3)
            } else if editingZoneIndex != nil {
                Button("Exit Edit") {
                    editingZoneIndex = nil
                    selectedVertexIndex = nil
                }
                .foregroundStyle(.secondary)
                Spacer()
                Text("Tap a corner to move it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    isDrawing = true
                } label: {
                    Label("Draw Zone", systemImage: "pencil.and.outline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private var suggestedLabel: String {
        let existing = zones.map { $0.label }
        let suggestions = ["Driveway", "Walkway", "Patio", "Side Path", "Back Area", "Front Lawn", "Zone \(zones.count + 1)"]
        return suggestions.first { !existing.contains($0) } ?? "Zone \(zones.count + 1)"
    }

    private func zoneColor(_ index: Int) -> Color {
        zoneColors[index % zoneColors.count]
    }

    private func zoneFillOpacity(_ zone: ZoneDraft) -> Double {
        guard zone.hasElevationData else { return 0.25 }
        switch zone.elevationGrade {
        case ..<2:   return 0.20
        case 2..<8:  return 0.35
        default:     return 0.50
        }
    }

    private func zoneCentroid(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let lat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
        let lon = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func approxDistanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let cosLat = cos(a.latitude * .pi / 180)
        let dx = (b.longitude - a.longitude) * cosLat * 111_000
        let dy = (b.latitude - a.latitude) * 111_000
        return sqrt(dx * dx + dy * dy)
    }

    private func pointInPolygon(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        let n = polygon.count
        var inside = false
        var j = n - 1
        for i in 0..<n {
            let xi = polygon[i].longitude, yi = polygon[i].latitude
            let xj = polygon[j].longitude, yj = polygon[j].latitude
            let intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
                (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)
            if intersect { inside = !inside }
            j = i
        }
        return inside
    }

    // MARK: - Save

    private func saveZones() {
        isSaving = true
        Task {
            for zone in client.sortedZones {
                modelContext.delete(zone)
            }
            for (index, draft) in zones.enumerated() {
                let grade = await ElevationService.shared.fetchGrade(for: draft.coordinates)
                let zone = PropertyZone(label: draft.label, rateType: draft.rateType, sortOrder: index)
                zone.setCoordinates(draft.coordinates)
                zone.areaSquareFeet = draft.areaSquareFeet
                zone.elevationGrade = grade
                zone.client = client
                modelContext.insert(zone)
            }
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}

// MARK: - Zone Label Sheet

struct ZoneLabelSheet: View {
    let suggestedLabel: String
    @Binding var pendingLabel: String
    let onDone: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Zone Label") {
                    TextField("e.g. Driveway", text: $pendingLabel)
                }
                Section {
                    ForEach(["Driveway", "Walkway", "Patio", "Side Path", "Back Area", "Front Lawn"], id: \.self) { suggestion in
                        Button(suggestion) { pendingLabel = suggestion }
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Suggestions")
                }
            }
            .navigationTitle("Name This Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                        onDone(false)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Zone") {
                        dismiss()
                        onDone(true)
                    }
                    .disabled(pendingLabel.isEmpty)
                }
            }
            .onAppear { pendingLabel = suggestedLabel }
        }
        .presentationDetents([.medium])
    }
}
