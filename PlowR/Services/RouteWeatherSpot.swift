import CoreLocation

/// Where the route screen's weather is for when there's no GPS fix to use
/// (a Mac, or location turned off): the current stop, or the first stop
/// after it, then before it, that's on the map. Stops are the job sites, so
/// their weather is the weather that matters. Nil: no stop has a pin.
nonisolated enum RouteWeatherSpot {
    /// Whether the weather comes from the stops: on a Mac (no route GPS) or
    /// with location refused. Not while the user hasn't answered yet, or
    /// while it's allowed: then the first GPS fix brings it.
    static func usesStops(isMac: Bool, status: CLAuthorizationStatus) -> Bool {
        isMac || status == .denied || status == .restricted
    }

    static func coordinate(stops: [(latitude: Double, longitude: Double)],
                           currentIndex: Int) -> CLLocationCoordinate2D? {
        let ahead = stops.indices.filter { $0 >= currentIndex }
        let behind = stops.indices.filter { $0 < currentIndex }.reversed()
        for index in ahead + behind {
            let stop = stops[index]
            guard AddressPin.exists(latitude: stop.latitude, longitude: stop.longitude) else { continue }
            let coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
            if CLLocationCoordinate2DIsValid(coordinate) { return coordinate }
        }
        return nil
    }
}
