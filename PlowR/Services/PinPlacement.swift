import CoreLocation
import Foundation

/// The rules of setting and moving a client's pin by hand (the pin screen,
/// LocationAdjustView, and what Edit Client does when it closes), kept
/// apart from the screens so they're tested. Nonisolated like
/// CoordinateBounds: plain values, used from tests off the main actor.
nonisolated enum PinPlacement {
    nonisolated struct Pin: Equatable {
        var latitude: Double
        var longitude: Double

        var exists: Bool { AddressPin.exists(latitude: latitude, longitude: longitude) }
    }

    /// How close the map must be before a pin can be set by hand: close
    /// enough to see the house. It opens zoomed out.
    static let streetDistance: Double = 800

    /// The map moved from where it opened: more than a couple of metres, as
    /// its first report on opening lands on the pin, give or take.
    static func moved(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)) > 2
    }

    /// Whether Confirm can be tapped: never mid-lookup, and for a pin set by
    /// hand only on a real spot at street zoom.
    static func canConfirm(hadPin: Bool, center: CLLocationCoordinate2D, distance: Double,
                                       isLookingUp: Bool) -> Bool {
        guard !isLookingUp else { return false }
        if hadPin { return true }
        return AddressPin.exists(latitude: center.latitude, longitude: center.longitude) && distance <= streetDistance
    }

    /// The address the map found where a moved pin is, offered on the pin
    /// screen for the user to take (Use This Address; Joe's call). It
    /// belongs to one spot: a move starts over, and a lookup's answer for a
    /// spot the pin has since left is ignored, so a failed or late lookup
    /// never offers the last spot's address.
    nonisolated struct Suggestion: Equatable {
        private(set) var spot: Pin?
        private(set) var found: String?
        var chosen = false

        mutating func moved(to newSpot: Pin) {
            self = Suggestion()
            spot = newSpot
        }

        mutating func found(_ address: String, at lookedUp: Pin) {
            guard lookedUp == spot else { return }
            found = address.isEmpty ? nil : address
            chosen = false
        }

        mutating func failed(at lookedUp: Pin) {
            guard lookedUp == spot else { return }
            found = nil
            chosen = false
        }

        /// What's offered: the address found here, when it isn't `current`
        /// written another way.
        func offer(differentFrom current: String) -> String? {
            guard let found, PinPlacement.differs(found, from: current) else { return nil }
            return found
        }
    }

    /// Two addresses differ beyond case, spaces and punctuation.
    static func differs(_ a: String, from b: String) -> Bool {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        return key(a) != key(b)
    }

    /// The address saved with a pin from the pin screen: the one the map
    /// found there only if the user chose it, and never for a pin set by
    /// hand, whose address the map couldn't find. Nil keeps the client's. It
    /// used to be written on every move: a reformatted version of the same
    /// address, or a neighbour's number.
    static func addressToSave(hadPin: Bool, suggestion: Suggestion, current: String) -> String? {
        guard hadPin, suggestion.chosen else { return nil }
        return suggestion.offer(differentFrom: current)
    }

    /// Whether Confirm saves anything. A pin being adjusted saves only if it
    /// moved: opening the screen looked its address up again, and Confirm
    /// wrote that (reformatted, or a neighbour's number) over the client's.
    static func saves(moved: Bool, hadPin: Bool) -> Bool { moved || !hadPin }

    /// Edit Client's address field, and the pin its Save would use.
    nonisolated struct Field: Equatable {
        /// What's in the field.
        var text: String
        /// The client's address as the screen knows it.
        var original: String
        var originalPin: Pin
        /// A picked suggestion's pin: typing drops it.
        var pickedPin: Pin?
        /// A pin from the pin screen, the client's address kept, that Save
        /// pairs with what's typed: one set for a client who had none, or
        /// one moved after a new address was typed. Typing keeps it, as the
        /// address is often still being fixed.
        var handPin: Pin?

        /// The pin Save writes with a changed address, instead of looking it
        /// up. A pick wins over a pin set by hand.
        var pinForSave: Pin? { pickedPin ?? handPin }

        /// After typing `newText`.
        func typed(_ newText: String) -> Field {
            var next = self
            next.text = newText
            next.pickedPin = nil
            return next
        }
    }

    /// `field` after the pin screen, or the property scanner's Move Pin,
    /// closed with the client at `storedAddress` and `storedPin`.
    static func field(_ field: Field, afterPinSheetWith storedAddress: String, _ storedPin: Pin) -> Field {
        guard storedPin != field.originalPin || storedAddress != field.original else { return field }  // cancelled
        var next = field
        next.originalPin = storedPin
        if storedAddress == field.original {
            // A pin set or moved by hand, the client's address kept: the
            // field keeps what's typed. Save writes it with this pin when
            // the pin was set for a client who had none (the map couldn't
            // find their address) or moved after a new address was typed.
            // A pin only nudged leaves an address typed later to be looked
            // up, as any changed address is.
            let typedFirst = field.text != field.original
            next.handPin = typedFirst || !field.originalPin.exists ? storedPin : nil
            next.pickedPin = nil
            return next
        }
        // The pin screen saved the address the map found there (Use This
        // Address): the field takes it.
        next.original = storedAddress
        next.text = storedAddress
        next.pickedPin = nil
        next.handPin = nil
        return next
    }
}
