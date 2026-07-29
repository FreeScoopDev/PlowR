import SwiftUI
import MapKit
import CoreLocation

struct ClientPropertyScanView: View {
    let business: BusinessResult
    let category: String
    let onComplete: ([ClientZoneDraft], String) -> Void

    @State private var addressText = ""
    @State private var isGeocoding = false
    @State private var geocodeError: String? = nil

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var confirmedAddress = ""
    @State private var addressConfirmed = false

    @State private var isDrawing = false
    @State private var currentPoints: [CLLocationCoordinate2D] = []
    @State private var zones: [LocalZoneDraft] = []
    @State private var showingLabelSheet = false
    @State private var pendingLabel = ""
    @State private var isSaving = false

    private let zoneColors: [Color] = [.blue, .green, .orange, .purple, .yellow]

    struct LocalZoneDraft: Identifiable {
        let id = UUID()
        var label: String
        var coordinates: [CLLocationCoordinate2D]
        var areaSquareFeet: Double
        var rateType: String = "perSqFt"
    }

    var body: some View {
        if addressConfirmed {
            mapView
        } else {
            addressEntryView
        }
    }

    // MARK: - Address Entry

    private var addressEntryView: some View {
        Form {
            Section {
                TextField("123 Main St, Springfield, IL", text: $addressText)
                    .textContentType(.fullStreetAddress)
                    .autocorrectionDisabled()
            } header: {
                Text("Your Property Address")
            } footer: {
                Text("We'll show a satellite view so you can outline the areas needing service.")
            }

            if let error = geocodeError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                Button {
                    Task { await confirmAddress() }
                } label: {
                    HStack {
                        Spacer()
                        if isGeocoding {
                            ProgressView()
                        } else {
                            Text("Show on Map")
                        }
                        Spacer()
                    }
                }
                .disabled(addressText.trimmingCharacters(in: .whitespaces).isEmpty || isGeocoding)
            }
        }
        .navigationTitle("Your Property")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func confirmAddress() async {
        isGeocoding = true
        geocodeError = nil
        do {
            let coord = try await geocode(addressText)
            await MainActor.run {
                confirmedAddress = addressText
                cameraPosition = .camera(MapCamera(centerCoordinate: coord, distance: 120, heading: 0, pitch: 0))
                addressConfirmed = true
                isGeocoding = false
            }
        } catch {
            await MainActor.run {
                geocodeError = "Address not found. Include city and state for best results."
                isGeocoding = false
            }
        }
    }

    private func geocode(_ address: String) async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            CLGeocoder().geocodeAddressString(address) { placemarks, error in
                if let coord = placemarks?.first?.location?.coordinate {
                    continuation.resume(returning: coord)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "PlowR.Geocoding", code: 0))
                }
            }
        }
    }

    // MARK: - Map View

    private var mapView: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            VStack(spacing: 0) {
                if isDrawing { drawingBanner }
                Spacer()
                controlPanel
            }
        }
        .navigationTitle("Map Your Property")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isDrawing {
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Next") { fetchElevationsAndContinue() }
                            .disabled(zones.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showingLabelSheet) {
            ZoneLabelSheet(suggestedLabel: suggestedLabel, pendingLabel: $pendingLabel) { confirmed in
                if confirmed, !currentPoints.isEmpty {
                    zones.append(LocalZoneDraft(
                        label: pendingLabel,
                        coordinates: currentPoints,
                        areaSquareFeet: currentPoints.enclosedAreaInSquareFeet()
                    ))
                }
                currentPoints = []
                isDrawing = false
                pendingLabel = ""
            }
        }
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    if zone.coordinates.count >= 3 {
                        MapPolygon(coordinates: zone.coordinates)
                            .foregroundStyle(zoneColors[index % zoneColors.count].opacity(0.25))
                            .stroke(zoneColors[index % zoneColors.count], lineWidth: 2)
                    }
                }
                if currentPoints.count >= 2 {
                    MapPolyline(coordinates: currentPoints).stroke(.yellow, lineWidth: 2)
                }
                ForEach(Array(currentPoints.enumerated()), id: \.offset) { index, coord in
                    Annotation("\(index + 1)", coordinate: coord) {
                        Circle().fill(.yellow).frame(width: 22, height: 22)
                            .overlay {
                                Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.black)
                            }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .onTapGesture { position in
                guard isDrawing else { return }
                if let coord = proxy.convert(position, from: .local) {
                    currentPoints.append(coord)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var drawingBanner: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
            Text("Tap the map to outline this zone").font(.subheadline)
            Spacer()
            if !currentPoints.isEmpty {
                Button("Undo") { currentPoints.removeLast() }.font(.subheadline)
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

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
                    Circle().fill(zoneColors[index % zoneColors.count]).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(zone.label).font(.subheadline).bold()
                        Text("\(Int(zone.areaSquareFeet)) sq ft").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { zones.remove(at: index) } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal).padding(.vertical, 8)
                Divider().padding(.leading)
            }
        }
        .frame(maxHeight: 200)
    }

    private var actionBar: some View {
        HStack {
            if isDrawing {
                Button("Cancel") { currentPoints = []; isDrawing = false }.foregroundStyle(.secondary)
                Spacer()
                Button("Close Zone") { showingLabelSheet = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentPoints.count < 3)
            } else {
                Button {
                    isDrawing = true
                } label: {
                    Label("Draw Zone", systemImage: "pencil.and.outline").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var suggestedLabel: String {
        let existing = zones.map { $0.label }
        let suggestions = ["Driveway", "Walkway", "Patio", "Side Path", "Back Area", "Front Lawn", "Zone \(zones.count + 1)"]
        return suggestions.first { !existing.contains($0) } ?? "Zone \(zones.count + 1)"
    }

    private func fetchElevationsAndContinue() {
        isSaving = true
        Task {
            var drafts: [ClientZoneDraft] = []
            for zone in zones {
                let grade = await ElevationService.shared.fetchGrade(for: zone.coordinates)
                drafts.append(ClientZoneDraft(
                    label: zone.label,
                    areaSquareFeet: zone.areaSquareFeet,
                    rateType: zone.rateType,
                    elevationGrade: grade,
                    coordinates: zone.coordinates
                ))
            }
            await MainActor.run {
                isSaving = false
                onComplete(drafts, confirmedAddress)
            }
        }
    }
}
