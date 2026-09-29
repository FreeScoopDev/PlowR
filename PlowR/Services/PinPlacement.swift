import CoreLocation
import Foundation

/// The rules of setting and moving a client's pin by hand (the pin screen,
/// LocationAdjustView, and what Edit Client does when it closes), kept
/// apart from the screens so they're tested.
enum PinPlacement {
    struct Pin: Equatable {
        var latitude: Double
        var longitude: Double

        nonisolated var exists: Bool { AddressPin.exists(latitude: latitude, longitude: longitude) }
    }

    /// How close the map must be before a pin can be set by hand: close
    /// enough to see the house. It opens zoomed out.
    nonisolated static let streetDistance: Double = 800

    /// The map moved from where it opened: more than a couple of metres, as
    /// its first report on opening lands on the pin, give or take.
    nonisolated static func moved(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)) > 2
    }

    /// Whether Confirm can be tapped: never mid-lookup, and for a pin set by
    /// hand only on a real spot at street zoom.
    nonisolated static func canConfirm(hadPin: Bool, center: CLLocationCoordinate2D, distance: Double,
                                       isLookingUp: Bool) -> Bool {
        guard !isLookingUp else { return false }
        if hadPin { return true }
        return AddressPin.exists(latitude: center.latitude, longitude: center.longitude) && distance <= streetDistance
    }

    /// Whether Confirm saves anything. A pin being adjusted saves only if it
    /// moved: opening the screen looked its address up again, and Confirm
    /// wrote that (reformatted, or a neighbour's number) over the client's.
    nonisolated static func saves(moved: Bool, hadPin: Bool) -> Bool { moved || !hadPin }

    /// Edit Client's address field, and the pin its Save would use.
    struct Field: Equatable {
        /// What's in the field.
        var text: String
        /// The client's address as the screen knows it.
        var original: String
        var originalPin: Pin
        /// A pin that goes with `text` (a picked suggestion's, or one set by
        /// hand): Save uses it instead of looking the address up.
        var pinForText: Pin?
    }

    /// `field` after the pin screen, or the property scanner's Move Pin,
    /// closed with the client at `storedAddress` and `storedPin`.
    nonisolated static func field(_ field: Field, afterPinSheetWith storedAddress: String, _ storedPin: Pin) -> Field {
        guard storedPin != field.originalPin || storedAddress != field.original else { return field }  // cancelled
        var next = field
        next.originalPin = storedPin
        if !field.originalPin.exists, storedAddress == field.original {
            // A pin set by hand for a client who had none. The address stays
            // as typed: if it was changed, Save writes it with this pin.
            next.pinForText = field.text != field.original ? storedPin : nil
            return next
        }
        // A pin moved, and the address the pin screen took with it.
        next.original = storedAddress
        next.text = storedAddress
        next.pinForText = nil
        return next
    }
}
