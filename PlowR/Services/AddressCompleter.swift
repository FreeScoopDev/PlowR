import MapKit
import Foundation

@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var completions: [MKLocalSearchCompletion] = []
    /// The address last picked from the suggestions, until the field shows it.
    var picked: String?
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String) {
        guard !query.isEmpty else { completions = []; return }
        completer.queryFragment = query
    }

    func clear() { completions = [] }

    /// The suggestion `address` was picked: the field is about to show it.
    func willPick(_ address: String) {
        picked = address
    }

    /// The address field changed to `text`. Typed: suggest addresses for it,
    /// and true, since a pin from an earlier pick no longer holds. The
    /// suggestion just picked: false, and no suggestions. The field's own
    /// change used to throw away the picked suggestion's pin and bring the
    /// list back.
    func fieldChanged(to text: String) -> Bool {
        if let picked, text == picked {
            self.picked = nil
            clear()
            return false
        }
        search(text)
        return true
    }

    // Resolve a completion to a full address string + coordinate
    func resolve(_ completion: MKLocalSearchCompletion) async -> (address: String, coordinate: CLLocationCoordinate2D?) {
        let parts = [completion.title, completion.subtitle].filter { !$0.isEmpty }
        let fullAddress = parts.joined(separator: ", ")
        willPick(fullAddress)
        let request = MKLocalSearch.Request(completion: completion)
        let coordinate = try? await MKLocalSearch(request: request).start()
            .mapItems.first?.location.coordinate
        return (fullAddress, coordinate)
    }

    // MARK: MKLocalSearchCompleterDelegate
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = Array(completer.results.prefix(5))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
    }
}
