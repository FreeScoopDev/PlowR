//
//  PinPlacementTests.swift
//  PlowRTests
//

import CoreLocation
import Testing
@testable import PlowR

/// Setting or moving a client's pin by hand: when the pin screen saves, when
/// its Confirm works, and what Edit Client's address field does after it.
struct PinPlacementTests {
    private let home = CLLocationCoordinate2D(latitude: 43.36385, longitude: -72.34377)

    private func offset(_ metres: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: home.latitude + metres / 111_320, longitude: home.longitude)
    }

    // Opening the screen reports the pin, give or take; a drag is more.
    @Test func movedMeansMoreThanTwoMetres() {
        #expect(!PinPlacement.moved(from: home, to: home))
        #expect(!PinPlacement.moved(from: home, to: offset(1)))
        #expect(PinPlacement.moved(from: home, to: offset(3)))
    }

    @Test func aPinSetByHandNeedsARealSpotAtStreetZoom() {
        let limit = PinPlacement.streetDistance
        #expect(PinPlacement.canConfirm(hadPin: false, center: home, distance: limit - 1, isLookingUp: false))
        #expect(!PinPlacement.canConfirm(hadPin: false, center: home, distance: limit + 1, isLookingUp: false))
        #expect(!PinPlacement.canConfirm(hadPin: false, center: .init(latitude: 0, longitude: 0), distance: 100,
                                         isLookingUp: false))
        #expect(PinPlacement.canConfirm(hadPin: true, center: home, distance: 5_000, isLookingUp: false))
        #expect(!PinPlacement.canConfirm(hadPin: true, center: home, distance: 80, isLookingUp: true))
    }

    // An adjusted pin that didn't move isn't saved: opening the screen looked
    // its address up again, and Confirm wrote that over the client's.
    @Test func onlyAMovedPinIsSaved() {
        #expect(!PinPlacement.saves(moved: false, hadPin: true))
        #expect(PinPlacement.saves(moved: true, hadPin: true))
        #expect(PinPlacement.saves(moved: false, hadPin: false))
    }

    // The address the map finds at a moved pin is only a suggestion: saved
    // when chosen, never for a pin set by hand.
    @Test func theFoundAddressIsSavedOnlyWhenChosen() {
        #expect(PinPlacement.addressToSave(hadPin: true, useFound: true, found: "12 Old Rd") == "12 Old Rd")
        #expect(PinPlacement.addressToSave(hadPin: true, useFound: false, found: "12 Old Rd") == nil)
        #expect(PinPlacement.addressToSave(hadPin: false, useFound: true, found: "12 Old Rd") == nil)
        #expect(PinPlacement.addressToSave(hadPin: true, useFound: true, found: "") == nil)
    }

    // MARK: - Edit Client's address field after the pin screen

    private let none = PinPlacement.Pin(latitude: 0, longitude: 0)
    private let old = PinPlacement.Pin(latitude: 43.3700, longitude: -72.3400)
    private let new = PinPlacement.Pin(latitude: 43.3639, longitude: -72.3438)

    @Test func aCancelledPinScreenChangesNothing() {
        let field = PinPlacement.Field(text: "10 Olde Rd", original: "10 Old Rd", originalPin: old)
        #expect(PinPlacement.field(field, afterPinSheetWith: "10 Old Rd", old) == field)
    }

    // A pin set by hand for a client with none keeps the address being typed,
    // and Save writes the two together. The field used to snap back.
    @Test func aPinSetByHandKeepsTheTypedAddress() {
        let typed = PinPlacement.Field(text: "10 Olde Rd", original: "10 Old Rd", originalPin: none)
        let after = PinPlacement.field(typed, afterPinSheetWith: "10 Old Rd", new)
        #expect(after == .init(text: "10 Olde Rd", original: "10 Old Rd", originalPin: new, handPin: new))
        #expect(after.pinForSave == new)
    }

    // The address the map couldn't find is often still being fixed: typing
    // keeps a pin set by hand, and drops a picked suggestion's.
    @Test func typingKeepsAHandPinButNotAPickedOne() {
        let hand = PinPlacement.Field(text: "10 Olde Rd", original: "10 Old Rd", originalPin: new, handPin: new)
        #expect(hand.typed("10 Olde Rd, Lot 14").pinForSave == new)
        let picked = PinPlacement.Field(text: "12 Elm St", original: "10 Old Rd", originalPin: old, pickedPin: new)
        #expect(picked.typed("12 Elm St, Apt 2").pinForSave == nil)
        let both = PinPlacement.Field(text: "12 Elm St", original: "10 Old Rd", originalPin: new,
                                      pickedPin: old, handPin: new)
        #expect(both.pinForSave == old)                        // a pick wins
    }

    // A pin moved takes the address the pin screen saved with it.
    @Test func aMovedPinBringsItsAddress() {
        let field = PinPlacement.Field(text: "10 Olde Rd", original: "10 Old Rd", originalPin: old, pickedPin: old)
        #expect(PinPlacement.field(field, afterPinSheetWith: "12 Old Rd Claremont NH 03743", new)
                == .init(text: "12 Old Rd Claremont NH 03743", original: "12 Old Rd Claremont NH 03743",
                         originalPin: new))
    }

    // Moved, but the pin screen couldn't look the new spot's address up: the
    // field still takes the client's (a typed address isn't paired with the
    // old house's nudged pin).
    @Test func aMovedPinWithTheSameAddressResetsTheField() {
        let field = PinPlacement.Field(text: "5 Elm St", original: "10 Old Rd", originalPin: old)
        #expect(PinPlacement.field(field, afterPinSheetWith: "10 Old Rd", new)
                == .init(text: "10 Old Rd", original: "10 Old Rd", originalPin: new))
    }
}
