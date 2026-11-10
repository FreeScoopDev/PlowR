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
        #expect(MapLinks.url(for: .googleMaps, to: addressOnly)?.absoluteString
                == "comgooglemaps://?daddr=Smith%20%26%20Sons,%205%20Elm%20St")
        // "#" would start a fragment and drop the rest of the address.
        let unit = MapLinks.Destination(latitude: 0, longitude: 0, address: "Unit #4, 5 Elm St")
        #expect(MapLinks.url(for: .googleMaps, to: unit)?.absoluteString
                == "comgooglemaps://?daddr=Unit%20%234,%205%20Elm%20St")
        #expect(MapLinks.url(for: .appleMaps, to: unit)?.absoluteString
                == "maps://?daddr=Unit%20%234,%205%20Elm%20St")
    }

    @Test func onlySpacesIsNoAddress() {
        let spaces = MapLinks.Destination(latitude: 0, longitude: 0, address: "   ")
        #expect(!spaces.isReachable)
        #expect(MapLinks.url(for: .appleMaps, to: spaces) == nil)
        #expect(MapLinks.apps(for: spaces, isInstalled: { _ in true }).isEmpty)
        let padded = MapLinks.Destination(latitude: 0, longitude: 0, address: " 5 Elm St ")
        #expect(MapLinks.url(for: .appleMaps, to: padded)?.absoluteString == "maps://?daddr=5%20Elm%20St")
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

    @Test func anExtensionIsNotDialedAsPartOfTheNumber() {
        #expect(MapLinks.callLink("555-010-0123 ext. 45")?.absoluteString == "tel:5550100123")
        #expect(MapLinks.callLink("555-010-0123 x45")?.absoluteString == "tel:5550100123")
        #expect(MapLinks.callLink("555-010-0123;45")?.absoluteString == "tel:5550100123")
    }

    @Test func aNumberFromAbroadKeepsItsPlus() {
        #expect(MapLinks.callLink("+44 20 7946 0958")?.absoluteString == "tel:+442079460958")
        #expect(MapLinks.callLink(" +1 (555) 010-0123")?.absoluteString == "tel:+15550100123")
        #expect(MapLinks.callLink("555+0123")?.absoluteString == "tel:5550123")
        #expect(MapLinks.callLink("+") == nil)
    }

    /// Only 0 to 9 can be dialed: other number characters made a link that rang nobody.
    @Test func onlyPlainDigitsAreDialed() {
        #expect(MapLinks.callLink("５５５ ０１００") == nil)
        #expect(MapLinks.callLink("555 0100 ½")?.absoluteString == "tel:5550100")
    }

    @Test func aLabelBeforeTheNumberStillDials() {
        #expect(MapLinks.callLink("Cell: 555-0100")?.absoluteString == "tel:5550100")
        #expect(MapLinks.callLink("office +1 555 010 0123")?.absoluteString == "tel:+15550100123")
    }

    @Test func callIsShownOnlyWithANumberOnADeviceThatCanCall() {
        #expect(MapLinks.canCall(phone: "555 010 0123", isMac: false, canOpenTel: true))
        #expect(!MapLinks.canCall(phone: "", isMac: false, canOpenTel: true))
        #expect(!MapLinks.canCall(phone: "555 010 0123", isMac: true, canOpenTel: true))
        #expect(!MapLinks.canCall(phone: "555 010 0123", isMac: false, canOpenTel: false))
    }
}
