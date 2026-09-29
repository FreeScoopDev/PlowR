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
        #expect(PinPlacement.canConfirm(hadPin: false, center: home, distance: limit - 1))
        #expect(!PinPlacement.canConfirm(hadPin: false, center: home, distance: limit + 1))
        #expect(!PinPlacement.canConfirm(hadPin: false, center: .init(latitude: 0, longitude: 0), distance: 100))
        #expect(PinPlacement.canConfirm(hadPin: true, center: home, distance: 5_000))
    }

    // An adjusted pin that didn't move isn't saved: opening the screen looked
    // its address up again, and Confirm wrote that over the client's.
    @Test func onlyAMovedPinIsSaved() {
        #expect(!PinPlacement.saves(moved: false, hadPin: true))
        #expect(PinPlacement.saves(moved: true, hadPin: true))
        #expect(PinPlacement.saves(moved: false, hadPin: false))
    }

    // MARK: - The address found at a moved pin

    private func found(_ address: String, at spot: PinPlacement.Pin, chosen: Bool = false) -> PinPlacement.Suggestion {
        var suggestion = PinPlacement.Suggestion()
        suggestion.moved(to: spot)
        suggestion.found(address, at: spot)
        suggestion.chosen = chosen
        return suggestion
    }

    // Only a suggestion: saved when chosen, never for a pin set by hand.
    @Test func theFoundAddressIsSavedOnlyWhenChosen() {
        let chosen = found("12 Old Rd, Claremont, NH 03743", at: new, chosen: true)
        #expect(PinPlacement.addressToSave(hadPin: true, suggestion: chosen, current: "10 Old Rd")
                == "12 Old Rd, Claremont, NH 03743")
        #expect(PinPlacement.addressToSave(hadPin: true, suggestion: found("12 Old Rd", at: new), current: "10 Old Rd")
                == nil)
        #expect(PinPlacement.addressToSave(hadPin: false, suggestion: chosen, current: "10 Old Rd") == nil)
        #expect(PinPlacement.addressToSave(hadPin: true, suggestion: .init(), current: "10 Old Rd") == nil)
    }

    // A suggestion belongs to one spot: a move starts over, and a late or
    // failed lookup never offers (or saves) the last spot's address.
    @Test func aSuggestionIsForOneSpot() {
        var suggestion = found("12 Old Rd", at: old, chosen: true)
        #expect(!suggestion.isLookingUp)
        suggestion.moved(to: new)
        #expect(suggestion.isLookingUp)                        // Confirm waits
        #expect(suggestion.offer(differentFrom: "10 Old Rd") == nil)
        #expect(!suggestion.chosen)
        suggestion.found("12 Old Rd", at: old)                  // the old spot's lookup, late
        #expect(suggestion.offer(differentFrom: "10 Old Rd") == nil)
        #expect(suggestion.isLookingUp)
        suggestion.found("14 Old Rd", at: new)
        #expect(!suggestion.isLookingUp)
        #expect(suggestion.offer(differentFrom: "10 Old Rd") == "14 Old Rd")
        suggestion.failed(at: old)                             // the old spot's, failing late
        #expect(suggestion.offer(differentFrom: "10 Old Rd") == "14 Old Rd")
        suggestion.chosen = true
        suggestion.failed(at: new)                             // looked up again, failed
        #expect(suggestion.offer(differentFrom: "10 Old Rd") == nil)
        suggestion.moved(to: old)
        suggestion.failed(at: old)                             // a new spot's lookup failed
        #expect(!suggestion.isLookingUp)
        #expect(PinPlacement.addressToSave(hadPin: true, suggestion: suggestion, current: "10 Old Rd") == nil)
    }

    // The client's own address, written another way, isn't offered: the
    // map's "12 Old Rd, Claremont, NH 03743" against an address suggestion's
    // "…, NH, United States", a street typed alone, Road for Rd, or case and
    // punctuation.
    @Test func theSameAddressWrittenDifferentlyIsntOffered() {
        let map = found("12 Old Rd, Claremont, NH 03743", at: new)
        for same in ["12 Old Rd, Claremont, NH, United States", "12 Old Rd", "12 old road claremont",
                     "12 OLD RD CLAREMONT NH 03743", "12 Old Rd, Apt 2, Claremont"] {
            #expect(map.offer(differentFrom: same) == nil, "\(same)")
        }
        let chosen = found("12 Old Rd, Claremont, NH 03743", at: new, chosen: true)
        #expect(PinPlacement.addressToSave(hadPin: true, suggestion: chosen, current: "12 Old Rd") == nil)
        for other in ["14 Old Rd, Claremont", "120 Old Rd", "12 Old Ridge Rd", "", "Old Rd, Claremont"] {
            #expect(map.offer(differentFrom: other) == "12 Old Rd, Claremont, NH 03743", "\(other)")
        }
    }

    // An answer with no house number would only lose detail; the map's
    // double space before the ZIP code is tidied.
    @Test func whatTheMapGivesIsTidiedOrLeft() {
        #expect(found("Claremont, NH  03743", at: new).offer(differentFrom: "12 Old Rd") == nil)
        #expect(found("233 Pleasant St, Claremont, NH  03743", at: new).offer(differentFrom: "12 Old Rd")
                == "233 Pleasant St, Claremont, NH 03743")
    }

    // A zoom that leaves the pin where it was looked up keeps the suggestion.
    @Test func onlyAMoveNeedsANewLookup() {
        let here = PinPlacement.Pin(latitude: home.latitude, longitude: home.longitude)
        var suggestion = PinPlacement.Suggestion()
        #expect(suggestion.needsLookup(at: here))
        suggestion.moved(to: here)
        #expect(!suggestion.needsLookup(at: .init(latitude: offset(1).latitude, longitude: offset(1).longitude)))
        #expect(suggestion.needsLookup(at: .init(latitude: offset(3).latitude, longitude: offset(3).longitude)))
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
        // Nothing typed yet: a fix typed afterwards still goes with this pin.
        let untyped = PinPlacement.Field(text: "10 Old Rd", original: "10 Old Rd", originalPin: none)
        #expect(PinPlacement.field(untyped, afterPinSheetWith: "10 Old Rd", new).typed("10 Olde Rd").pinForSave == new)
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

    // A pin moved by hand with the client's address kept (the usual Adjust
    // Pin now): a new address typed before stays, and Save writes it with
    // the moved pin. It used to snap back to the old address.
    @Test func aPinMovedByHandKeepsTheTypedAddress() {
        let typed = PinPlacement.Field(text: "45 New St", original: "10 Old Rd", originalPin: old)
        let after = PinPlacement.field(typed, afterPinSheetWith: "10 Old Rd", new)
        #expect(after == .init(text: "45 New St", original: "10 Old Rd", originalPin: new, handPin: new))
        #expect(after.pinForSave == new)
    }

    // The map's address taken on the pin screen goes in the field, whatever
    // was typed: even the client's saved address, taken back, which the
    // client's record alone can't tell from no choice at all.
    @Test func anAddressTakenOnThePinScreenFillsTheField() {
        let typed = PinPlacement.Field(text: "5 New St", original: "1 Old Rd, Claremont, NH 03743", originalPin: old)
        let back = PinPlacement.field(typed, afterPinSheetWith: "1 Old Rd, Claremont, NH 03743", new,
                                      chosen: "1 Old Rd, Claremont, NH 03743")
        #expect(back == .init(text: "1 Old Rd, Claremont, NH 03743", original: "1 Old Rd, Claremont, NH 03743",
                              originalPin: new))
        #expect(back.pinForSave == nil)
        let neighbour = PinPlacement.field(typed, afterPinSheetWith: "3 Old Rd, Claremont, NH 03743", new,
                                           chosen: "3 Old Rd, Claremont, NH 03743")
        #expect(neighbour.text == "3 Old Rd, Claremont, NH 03743" && neighbour.pinForSave == nil)
    }

    // A pin only nudged, nothing typed: an address typed afterwards is looked
    // up as usual, not saved with the nudged pin (the client may have moved).
    @Test func aNudgedPinDoesntVouchForAnAddressTypedLater() {
        let untouched = PinPlacement.Field(text: "10 Old Rd", original: "10 Old Rd", originalPin: old)
        let after = PinPlacement.field(untouched, afterPinSheetWith: "10 Old Rd", new)
        #expect(after == .init(text: "10 Old Rd", original: "10 Old Rd", originalPin: new))
        #expect(after.typed("45 New St").pinForSave == nil)
    }
}
