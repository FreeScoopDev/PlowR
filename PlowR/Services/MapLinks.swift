import Foundation
import UIKit

/// Where a drive or a call goes, and the links that open it. One place for the
/// route screen's Navigate and the client page's Directions, so both offer the
/// same apps and build the same links. Pure logic, except `installed`, `open`
/// and `canPlaceCalls`, which ask the system.
nonisolated enum MapLinks {
    /// A place to drive to: its pin when it has one, else its address.
    struct Destination: Equatable {
        var latitude: Double
        var longitude: Double
        var address: String

        /// Same rule the route screen always used: a latitude of 0 is no pin.
        var hasPin: Bool { latitude != 0 }
        /// Something to drive to: a pin, or an address with text in it.
        var isReachable: Bool { hasPin || !address.isEmpty }
    }

    enum App: CaseIterable {
        case appleMaps, googleMaps, waze

        var title: String {
            switch self {
            case .appleMaps: "Apple Maps"
            case .googleMaps: "Google Maps"
            case .waze: "Waze"
            }
        }

        /// The scheme to ask `canOpenURL` about; Apple Maps is always there.
        /// Each must be in `LSApplicationQueriesSchemes` (Info.plist).
        var probeScheme: String? {
            switch self {
            case .appleMaps: nil
            case .googleMaps: "comgooglemaps://"
            case .waze: "waze://"
            }
        }
    }

    /// What a query value may leave unencoded: `.urlQueryAllowed` keeps `&`,
    /// `=` and `+`, so "Smith & Sons, 5 Elm St" ended the address at "Smith ".
    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))

    /// Driving directions in `app`, or nil when it can't be told where to go
    /// (no pin and no address, or Waze with no pin).
    static func url(for app: App, to place: Destination) -> URL? {
        guard place.isReachable else { return nil }
        switch app {
        case .appleMaps:
            if place.hasPin {
                return URL(string: "maps://?daddr=\(place.latitude),\(place.longitude)&dirflg=d")
            }
            let address = place.address.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
            return URL(string: "maps://?daddr=\(address)")
        case .googleMaps:
            if place.hasPin {
                return URL(string: "comgooglemaps://?daddr=\(place.latitude),\(place.longitude)&directionsmode=driving")
            }
            // As the route screen has always encoded it for Google Maps.
            let address = place.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "comgooglemaps://?daddr=\(address)")
        case .waze:
            guard place.hasPin else { return nil }
            return URL(string: "waze://?ll=\(place.latitude),\(place.longitude)&navigate=yes")
        }
    }

    /// The apps to offer: Apple Maps always (when there is anywhere to go),
    /// Google Maps and Waze when `isInstalled` says so for their scheme. Waze
    /// takes a pin only, so a place with just an address isn't offered it.
    static func apps(for place: Destination, isInstalled: (String) -> Bool) -> [App] {
        guard place.isReachable else { return [] }
        return App.allCases.filter { app in
            guard url(for: app, to: place) != nil else { return false }
            guard let scheme = app.probeScheme else { return true }
            return isInstalled(scheme)
        }
    }

    /// `apps(for:isInstalled:)` asked of this device.
    @MainActor
    static func installedApps(for place: Destination) -> [App] {
        apps(for: place) { scheme in
            URL(string: scheme).map { UIApplication.shared.canOpenURL($0) } ?? false
        }
    }

    @MainActor
    static func open(_ app: App, to place: Destination) {
        if let url = url(for: app, to: place) { UIApplication.shared.open(url) }
    }

    // MARK: - Calls

    /// The link that places a call to `phone`: its digits only, so "(555)
    /// 010-0123" dials. Nil when there are no digits.
    static func callLink(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    /// Whether to show Call: a number to dial, and a device that can place a
    /// call. `canOpenTel` is the system's answer for `tel:`.
    static func canCall(phone: String, isMac: Bool, canOpenTel: Bool) -> Bool {
        !isMac && canOpenTel && callLink(phone) != nil
    }

    /// `canCall` asked of this device (a Mac, or an iPad without calling, says no).
    @MainActor
    static func canCall(phone: String) -> Bool {
        let tel = URL(string: "tel:0").map { UIApplication.shared.canOpenURL($0) } ?? false
        return canCall(phone: phone, isMac: OnMac.isMac, canOpenTel: tel)
    }
}
