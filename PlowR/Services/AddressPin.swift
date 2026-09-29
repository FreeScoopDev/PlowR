import CoreLocation
import Foundation
import MapKit

/// A client's map pin, from their address. 0,0 is "no pin": what a client
/// gets when their address can't be put on the map. (Some older screens
/// check the latitude alone.)
enum AddressPin {
    /// Whether `latitude`, `longitude` is a pin. Both must be checked: a
    /// place on the equator or the prime meridian has one of them at 0.
    nonisolated static func exists(latitude: Double, longitude: Double) -> Bool {
        latitude != 0 || longitude != 0
    }

    /// What looking an address up gave.
    enum Lookup: Equatable {
        case found(latitude: Double, longitude: Double)
        case failed(Problem)
    }

    /// Why an address got no pin.
    enum Problem: Equatable {
        /// The map doesn't know it: a new street, a typo.
        case notFound
        /// The map couldn't be reached (no signal, say), so it may well
        /// exist: worth trying again.
        case unreachable

        var title: String {
            switch self {
            case .notFound: "Address Not Found"
            case .unreachable: "Couldn't Reach the Map"
            }
        }

        var message: String {
            let withoutPin = "Without a pin, the client isn't on route maps and gets no drive times or "
                + "job-site alerts. You can save them without one and set the pin on their page."
            switch self {
            case .notFound: return "PlowR couldn't find this address on the map. " + withoutPin
            case .unreachable: return "PlowR couldn't reach the map to look this address up: no signal, "
                + "or the map is busy. Try again in a moment. " + withoutPin
            }
        }
    }

    /// `address` on the map. It used to be looked up with `CLGeocoder`
    /// (deprecated in iOS 26), and any failure was dropped: the client was
    /// saved with no pin, or kept the old address's pin, and nothing said so.
    static func lookUp(_ address: String) async -> Lookup {
        guard let request = MKGeocodingRequest(addressString: address) else { return .failed(.notFound) }
        do {
            guard let location = try await request.mapItems.first?.location else { return .failed(.notFound) }
            return .found(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        } catch {
            return .failed(problem(for: error))
        }
    }

    /// Puts a new client on the map. Nil when their address was found (the
    /// client now has its pin); otherwise why not.
    static func place(_ client: Client) async -> Problem? {
        switch await lookUp(client.address) {
        case let .found(latitude, longitude):
            client.latitude = latitude
            client.longitude = longitude
            return nil
        case .failed(let problem):
            return problem
        }
    }

    /// A lookup's error: the map said it doesn't know the address, or
    /// anything else (network, server, throttling), which a retry may fix.
    nonisolated static func problem(for error: Error) -> Problem {
        let error = error as NSError
        switch error.domain {
        case MKErrorDomain where error.code == Int(MKError.Code.placemarkNotFound.rawValue):
            return .notFound
        case kCLErrorDomain where error.code == CLError.Code.geocodeFoundNoResult.rawValue:
            return .notFound
        default:
            return .unreachable
        }
    }
}
