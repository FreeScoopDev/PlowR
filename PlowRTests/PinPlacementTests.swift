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

    // MARK: - Edit Client's address field after the pin screen

    private let none = PinPlacement.Pin(latitude: 0, longitude: 0)
    private let old = PinPlacement.Pin(latitude: 43.3700, longitude: -72.3400)
    private let new = PinPlacement.Pin(latitude: 43.3639, longitude: -72.3438)

    @Test func aCancelledPinScreenChangesNothing() {
        let field = PinPlacement.Field(text: "10 Olde Rd", original: "10 Old Rd", originalPin: old, pinForText: nil)
        #expect(PinPlacement.field(field, afterPinSheetWith: "10 Old Rd", old) == field)
    }

    // A pin set by hand for a client with none keeps the address being typed,
    // and Save writes the two together. The field used to snap back.
    @Test func aPinSetByHandKeepsTheTypedAddress() {
        let typed = PinPlacement.Field(text: "10 Olde Rd", original: "10 Old Rd", originalPin: none, pinForText: nil)
        #expect(PinPlacement.field(typed, afterPinSheetWith: "10 Old Rd", new)
                == .init(text: "10 Olde Rd", original: "10 Old Rd", originalPin: new, pinForText: new))
        let untouched = PinPlacement.Field(text: "10 Old Rd", original: "10 Old Rd", originalPin: none, pinForText: nil)
        #expect(PinPlacement.field(untouched, afterPinSheetWith: "10 Old Rd", new)
                == .init(text: "10 Old Rd", original: "10 Old Rd", originalPin: new, pinForText: nil))
    }

    // A pin moved takes the address the pin screen saved with it.
    @Test func aMovedPinBringsItsAddress() {
        let field = PinPlacement.Field(text: "10 Olde Rd", original: "10 Old Rd", originalPin: old, pinForText: old)
        #expect(PinPlacement.field(field, afterPinSheetWith: "12 Old Rd Claremont NH 03743", new)
                == .init(text: "12 Old Rd Claremont NH 03743", original: "12 Old Rd Claremont NH 03743",
                         originalPin: new, pinForText: nil))
    }
}
