//
//  AddressPinTests.swift
//  PlowRTests
//

import CoreLocation
import Foundation
import MapKit
import Testing
@testable import PlowR

/// A client's map pin, from their address. An address the map can't find,
/// or can't look up, used to be saved without a pin (or with the old one)
/// and nothing said so; now the screens ask, and say which it was.
@MainActor
struct AddressPinTests {
    @Test func zeroZeroIsNoPin() {
        #expect(!AddressPin.exists(latitude: 0, longitude: 0))
    }

    @Test func anyRealPlaceIsAPin() {
        #expect(AddressPin.exists(latitude: 43.3767, longitude: -72.3468))    // Claremont, NH
        #expect(AddressPin.exists(latitude: 0, longitude: 9.45))              // on the equator
        #expect(AddressPin.exists(latitude: 51.48, longitude: 0))             // on the meridian
    }

    // "Check the address" only when the map said it doesn't know it; any
    // other failure (no signal, a server error) may pass on a retry.
    @Test func onlyAnUnknownAddressIsNotFound() {
        #expect(AddressPin.problem(for: MKError(.placemarkNotFound)) == .notFound)
        #expect(AddressPin.problem(for: CLError(.geocodeFoundNoResult)) == .notFound)
        #expect(AddressPin.problem(for: URLError(.notConnectedToInternet)) == .unreachable)
        #expect(AddressPin.problem(for: CLError(.network)) == .unreachable)
        #expect(AddressPin.problem(for: MKError(.serverFailure)) == .unreachable)
        #expect(AddressPin.problem(for: MKError(.loadingThrottled)) == .unreachable)
    }

    @Test func eachProblemSaysWhatHappened() {
        #expect(AddressPin.Problem.notFound.title == "Address Not Found")
        #expect(AddressPin.Problem.unreachable.title == "Couldn't Reach the Map")
        for hasPin in [false, true] {
            #expect(AddressPin.Problem.notFound.message(hasPin: hasPin)
                .hasPrefix("PlowR couldn't find this address on the map."))
            #expect(AddressPin.Problem.unreachable.message(hasPin: hasPin).contains("Try again"))
            #expect(!AddressPin.Problem.notFound.message(hasPin: hasPin).contains("Try again"))
        }
        for problem in [AddressPin.Problem.notFound, .unreachable] {
            #expect(problem.message(hasPin: false).contains("set the pin on their page"))
            #expect(problem.message(hasPin: true).contains("keep the client's current pin"))
        }
    }

    // Joe's call: a client who has a pin keeps it or has the address typed
    // again; one without is saved without one, or the address typed again.
    @Test func theAlertOffersWhatFitsTheClient() {
        typealias C = AddressPin.Choice
        #expect(AddressPin.Problem.notFound.choices(hasPin: false) == [C.saveWithoutPin, .editAddress])
        #expect(AddressPin.Problem.notFound.choices(hasPin: true) == [C.keepCurrentPin, .editAddress])
        #expect(AddressPin.Problem.unreachable.choices(hasPin: false) == [C.tryAgain, .saveWithoutPin, .editAddress])
        #expect(AddressPin.Problem.unreachable.choices(hasPin: true) == [C.tryAgain, .keepCurrentPin, .editAddress])
    }

    // Picking a suggestion sets the field; that change isn't typing, so its
    // pin stays and the list doesn't come back. The field used to throw the
    // picked suggestion's pin away.
    @Test func aPickedSuggestionIsntTyping() {
        let completer = AddressCompleter()
        completer.willPick("12 Pleasant St, Claremont, NH")
        #expect(!completer.fieldChanged(to: "12 Pleasant St, Claremont, NH"))
        #expect(completer.picked == nil)
        #expect(completer.fieldChanged(to: "12 Pleasant St, Claremont, NH"))   // typed again later
        #expect(completer.fieldChanged(to: "14 Pleasant"))
    }
}
