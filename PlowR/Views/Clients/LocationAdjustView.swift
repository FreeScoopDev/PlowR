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
    @State private var isGeocoding = false
    /// The address the map found where the pin is, to take or leave.
    @State private var suggestion = PinPlacement.Suggestion()
    @State private var lookup: Task<Void, Never>?
    /// The map was moved from the pin it opened on. Only then is anything
    /// saved: opening the screen looked the pin's address up again, and
    /// Confirm wrote that back over the client's.
    @State private var moved = false
    /// The client had a pin to adjust. Without one (their address couldn't
    /// be found) the pin is set here, and the map starts where the user is,
    /// or around the business's other clients, not at 0,0 in the ocean.
    private let hadPin: Bool
    private let openedAt: CLLocationCoordinate2D

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
    }

    /// Where a pinless client's map starts when the user's location isn't
    /// known: around the business's other clients.
    private var otherClientsRegion: MKCoordinateRegion? {
        let pins = clients
            .filter { $0.operatorID == client.operatorID && AddressPin.exists(latitude: $0.latitude, longitude: $0.longitude) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        return CoordinateBounds(pins)?.region()
    }

    private var canConfirm: Bool {
        PinPlacement.canConfirm(hadPin: hadPin, center: centerCoordinate, distance: cameraDistance,
                                isLookingUp: isGeocoding)
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
                if PinPlacement.moved(from: openedAt, to: centerCoordinate) { moved = true }
                // A pin set by hand keeps the address as typed (the map
                // couldn't find it): nothing to look up.
                // A zoom that leaves the pin where it was keeps the suggestion
                // (and a choice already made); a move starts it over.
                let lastSpot = suggestion.spot.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                if hadPin, moved, lastSpot.map({ PinPlacement.moved(from: $0, to: centerCoordinate) }) ?? true {
                    let spot = PinPlacement.Pin(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
                    suggestion.moved(to: spot)
                    lookUpAddress(at: spot)
                }
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
                    // The address that's kept, unless the user takes the one
                    // the map found here.
                    let offered = suggestion.offer(differentFrom: client.address)
                    Text(suggestion.chosen ? (offered ?? client.address)
                         : (client.address.isEmpty ? "No address" : client.address))
                        .font(.subheadline.weight(.medium))
                        .animation(.easeInOut(duration: 0.2), value: suggestion.chosen)
                    if isGeocoding {
                        Text("Finding the address here…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let offered {
                        HStack(spacing: 6) {
                            Text("The map shows \(offered) here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(suggestion.chosen ? "Keep Client's Address" : "Use This Address") {
                                suggestion.chosen.toggle()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
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

    /// Looks up the address at `spot`. A newer move cancels an older lookup,
    /// and the suggestion ignores an answer for a spot the pin has left.
    private func lookUpAddress(at spot: PinPlacement.Pin) {
        lookup?.cancel()
        isGeocoding = true
        lookup = Task {
            let location = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            guard !Task.isCancelled else { return }
            // "12 Old Rd, Claremont, NH 03743", the way addresses are typed.
            let street = [placemark?.subThoroughfare, placemark?.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let region = [placemark?.administrativeArea, placemark?.postalCode].compactMap { $0 }.joined(separator: " ")
            let address = [street, placemark?.locality ?? "", region].filter { !$0.isEmpty }.joined(separator: ", ")
            if address.isEmpty {
                suggestion.failed(at: spot)
            } else {
                suggestion.found(address, at: spot)
            }
            if suggestion.spot == spot { isGeocoding = false }
        }
    }

    private var hint: String {
        if hadPin { return "Drag the map to reposition the pin" }
        return cameraDistance <= PinPlacement.streetDistance
            ? "Drag the map until the pin is on the house"
            : "Zoom in to the house, then drag the map to it"
    }

    private func saveAndDismiss() {
        guard PinPlacement.saves(moved: moved, hadPin: hadPin) else { return dismiss() }
        let address = PinPlacement.addressToSave(hadPin: hadPin, suggestion: suggestion, current: client.address)
        if let onSave {
            // Caller handles the update (e.g. PropertyScannerView before zones
            // are saved); it keeps the client's address when given none.
            onSave(centerCoordinate, address ?? "")
        } else {
            // Direct SwiftData model update (EditClientView path)
            client.latitude = centerCoordinate.latitude
            client.longitude = centerCoordinate.longitude
            if let address { client.address = address }
            ClientStops.update(for: client)
        }
        dismiss()
    }
}
