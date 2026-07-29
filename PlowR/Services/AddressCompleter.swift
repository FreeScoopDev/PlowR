import MapKit
import Foundation

@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var completions: [MKLocalSearchCompletion] = []
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

    // Resolve a completion to a full address string + coordinate
    func resolve(_ completion: MKLocalSearchCompletion) async -> (address: String, coordinate: CLLocationCoordinate2D?) {
        let parts = [completion.title, completion.subtitle].filter { !$0.isEmpty }
        let fullAddress = parts.joined(separator: ", ")
        let request = MKLocalSearch.Request(completion: completion)
        let coordinate = try? await MKLocalSearch(request: request).start()
            .mapItems.first?.placemark.coordinate
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
