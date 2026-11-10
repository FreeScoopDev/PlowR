//
//  MapLinksTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// The links behind the route screen's Navigate and the client page's
/// Directions and Call, and which apps are offered.
struct MapLinksTests {
    private let pinned = MapLinks.Destination(latitude: 43.5, longitude: -72.25, address: "5 Elm St")
    private let addressOnly = MapLinks.Destination(latitude: 0, longitude: 0, address: "Smith & Sons, 5 Elm St")
    private let nowhere = MapLinks.Destination(latitude: 0, longitude: 0, address: "")

    @Test func aPinIsUsedInsteadOfTheAddress() {
        #expect(MapLinks.url(for: .appleMaps, to: pinned)?.absoluteString == "maps://?daddr=43.5,-72.25&dirflg=d")
        #expect(MapLinks.url(for: .googleMaps, to: pinned)?.absoluteString
                == "comgooglemaps://?daddr=43.5,-72.25&directionsmode=driving")
        #expect(MapLinks.url(for: .waze, to: pinned)?.absoluteString == "waze://?ll=43.5,-72.25&navigate=yes")
    }

    @Test func withNoPinTheAddressIsUsedAndEncoded() {
        // "&" must be encoded for Apple Maps or the address ends at "Smith ".
        #expect(MapLinks.url(for: .appleMaps, to: addressOnly)?.absoluteString
                == "maps://?daddr=Smith%20%26%20Sons,%205%20Elm%20St")
        let google = MapLinks.url(for: .googleMaps, to: addressOnly)?.absoluteString
        #expect(google?.hasPrefix("comgooglemaps://?daddr=Smith%20") == true)
        #expect(google?.contains(" ") == false)
    }

    @Test func wazeNeedsAPin() {
        #expect(MapLinks.url(for: .waze, to: addressOnly) == nil)
    }

    @Test func noPinAndNoAddressGivesNothing() {
        for app in MapLinks.App.allCases {
            #expect(MapLinks.url(for: app, to: nowhere) == nil)
        }
        #expect(MapLinks.apps(for: nowhere, isInstalled: { _ in true }).isEmpty)
        #expect(!nowhere.isReachable)
    }

    @Test func appleMapsIsAlwaysOfferedAndOthersOnlyWhenInstalled() {
        #expect(MapLinks.apps(for: pinned, isInstalled: { _ in false }) == [.appleMaps])
        #expect(MapLinks.apps(for: pinned, isInstalled: { $0 == "waze://" }) == [.appleMaps, .waze])
        #expect(MapLinks.apps(for: pinned, isInstalled: { _ in true }) == [.appleMaps, .googleMaps, .waze])
    }

    @Test func wazeIsNotOfferedWhereItCouldNotBeSentAnywhere() {
        #expect(MapLinks.apps(for: addressOnly, isInstalled: { _ in true }) == [.appleMaps, .googleMaps])
    }

    @Test func aCallDialsTheDigitsOnly() {
        #expect(MapLinks.callLink("(555) 010-0123")?.absoluteString == "tel:5550100123")
        #expect(MapLinks.callLink("") == nil)
        #expect(MapLinks.callLink("n/a") == nil)
    }

    @Test func callIsShownOnlyWithANumberOnADeviceThatCanCall() {
        #expect(MapLinks.canCall(phone: "555 010 0123", isMac: false, canOpenTel: true))
        #expect(!MapLinks.canCall(phone: "", isMac: false, canOpenTel: true))
        #expect(!MapLinks.canCall(phone: "555 010 0123", isMac: true, canOpenTel: true))
        #expect(!MapLinks.canCall(phone: "555 010 0123", isMac: false, canOpenTel: false))
    }
}
