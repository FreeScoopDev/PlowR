import SwiftUI
import MapKit
import CoreLocation

struct LocationAdjustView: View {
    let client: Client
    let onSave: ((CLLocationCoordinate2D, String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition
    @State private var centerCoordinate: CLLocationCoordinate2D
    @State private var resolvedAddress: String
    @State private var isGeocoding = false

    init(client: Client, onSave: ((CLLocationCoordinate2D, String) -> Void)? = nil) {
        self.client = client
        self.onSave = onSave
        let coord = CLLocationCoordinate2D(latitude: client.latitude, longitude: client.longitude)
        _cameraPosition = State(initialValue: .camera(MapCamera(centerCoordinate: coord, distance: 80)))
        _centerCoordinate = State(initialValue: coord)
        _resolvedAddress = State(initialValue: client.address)
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
                reverseGeocode(centerCoordinate)
            }
            .navigationTitle("Adjust Location")
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
                    Text("Drag the map to reposition the pin")
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
                    .disabled(isGeocoding)
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

    private func saveAndDismiss() {
        if let onSave {
            // Caller handles the update (e.g. PropertyScannerView before zones are saved)
            onSave(centerCoordinate, resolvedAddress)
        } else {
            // Direct SwiftData model update (EditClientView path)
            client.latitude = centerCoordinate.latitude
            client.longitude = centerCoordinate.longitude
            if !resolvedAddress.isEmpty {
                client.address = resolvedAddress
            }
        }
        dismiss()
    }
}
