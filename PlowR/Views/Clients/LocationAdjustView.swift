import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct LocationAdjustView: View {
    let client: Client
    let onSave: ((CLLocationCoordinate2D, String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Query private var clients: [Client]

    @State private var cameraPosition: MapCameraPosition
    @State private var centerCoordinate: CLLocationCoordinate2D
    @State private var cameraDistance: Double
    @State private var resolvedAddress: String
    @State private var isGeocoding = false
    /// The map was moved from the pin it opened on. Only then is anything
    /// saved: opening the screen looked the pin's address up again, and
    /// Confirm wrote that back over the client's.
    @State private var moved = false
    /// The client had a pin to adjust. Without one (their address couldn't
    /// be found) the pin is set here, and the map starts where the user is,
    /// or around the business's other clients, not at 0,0 in the ocean.
    private let hadPin: Bool
    private let openedAt: CLLocationCoordinate2D

    /// How close the map must be before a pin can be set by hand: close
    /// enough to see the house.
    static let streetDistance: Double = 2_000

    init(client: Client, onSave: ((CLLocationCoordinate2D, String) -> Void)? = nil) {
        self.client = client
        self.onSave = onSave
        let coord = CLLocationCoordinate2D(latitude: client.latitude, longitude: client.longitude)
        hadPin = AddressPin.exists(latitude: coord.latitude, longitude: coord.longitude)
        openedAt = coord
        _cameraPosition = State(initialValue: hadPin
            ? .camera(MapCamera(centerCoordinate: coord, distance: 80)) : .automatic)
        _centerCoordinate = State(initialValue: coord)
        _cameraDistance = State(initialValue: hadPin ? 80 : .infinity)
        _resolvedAddress = State(initialValue: client.address)
    }

    /// Where a pinless client's map starts when the user's location isn't
    /// known: around the business's other clients.
    private var otherClientsRegion: MKCoordinateRegion? {
        let pins = clients
            .filter { $0.operatorID == client.operatorID && AddressPin.exists(latitude: $0.latitude, longitude: $0.longitude) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        return CoordinateBounds(pins)?.region()
    }

    /// Confirm needs a real spot: for a pin set by hand, the map zoomed in
    /// to street level (it starts zoomed out).
    private var canConfirm: Bool {
        guard !isGeocoding else { return false }
        if hadPin { return true }
        return AddressPin.exists(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
            && cameraDistance <= Self.streetDistance
    }

    var body: some View {
        Map(position: $cameraPosition)
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControls {
                MapScaleView()
                MapCompass()
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .center) {
                pinView
            }
            .safeAreaInset(edge: .bottom) {
                confirmationPanel
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                centerCoordinate = context.camera.centerCoordinate
                cameraDistance = context.camera.distance
                let from = CLLocation(latitude: openedAt.latitude, longitude: openedAt.longitude)
                let to = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
                if from.distance(from: to) > 2 { moved = true }
                // A pin set by hand keeps the address as typed (the map
                // couldn't find it): nothing to look up.
                if hadPin, moved { reverseGeocode(centerCoordinate) }
            }
            .onAppear {
                guard !hadPin else { return }
                cameraPosition = .userLocation(fallback: otherClientsRegion.map { .region($0) } ?? .automatic)
            }
            .navigationTitle(hadPin ? "Adjust Location" : "Set Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
    }

    // Fixed center pin — dot marks the exact saved coordinate
    private var pinView: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                Image(systemName: "house.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Rectangle()
                .fill(Color.blue)
                .frame(width: 2.5, height: 22)
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
        }
        // Shift up so the bottom dot sits at the screen center, not the icon
        .offset(y: -37)
        .allowsHitTesting(false)
    }

    private var confirmationPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isGeocoding ? "arrow.triangle.2.circlepath" : "mappin.circle.fill")
                    .foregroundStyle(isGeocoding ? Color(.secondaryLabel) : Color.blue)
                    .symbolEffect(.rotate, isActive: isGeocoding)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isGeocoding ? "Finding address…" : (resolvedAddress.isEmpty ? "Unknown location" : resolvedAddress))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isGeocoding ? .secondary : .primary)
                        .animation(.easeInOut(duration: 0.2), value: resolvedAddress)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("Confirm Location") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!canConfirm)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) {
        isGeocoding = true
        Task {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                var parts: [String] = []
                if let number = placemark.subThoroughfare { parts.append(number) }
                if let street = placemark.thoroughfare { parts.append(street) }
                if let city = placemark.locality { parts.append(city) }
                if let state = placemark.administrativeArea { parts.append(state) }
                if let zip = placemark.postalCode { parts.append(zip) }
                let address = parts.joined(separator: " ")
                await MainActor.run {
                    resolvedAddress = address.isEmpty ? client.address : address
                    isGeocoding = false
                }
            } else {
                await MainActor.run { isGeocoding = false }
            }
        }
    }

    private var hint: String {
        if hadPin { return "Drag the map to reposition the pin" }
        return cameraDistance <= Self.streetDistance
            ? "Drag the map until the pin is on the house"
            : "Zoom in to the house, then drag the map to it"
    }

    private func saveAndDismiss() {
        // Nothing moved: nothing to save.
        guard moved || !hadPin else { return dismiss() }
        if let onSave {
            // Caller handles the update (e.g. PropertyScannerView before zones are saved)
            onSave(centerCoordinate, resolvedAddress)
        } else {
            // Direct SwiftData model update (EditClientView path)
            client.latitude = centerCoordinate.latitude
            client.longitude = centerCoordinate.longitude
            // A pin set by hand is for an address the map couldn't find: the
            // nearest address it knows would replace the one the user typed.
            if hadPin, !resolvedAddress.isEmpty {
                client.address = resolvedAddress
            }
            ClientStops.update(for: client)
        }
        dismiss()
    }
}
