import CoreLocation

/// Where the route screen's weather is for when there's no GPS fix to use
/// (a Mac, or location turned off): the current stop, or the first stop
/// after it, then before it, that's on the map. Stops are the job sites, so
/// their weather is the weather that matters. Nil: no stop has a pin.
nonisolated enum RouteWeatherSpot {
    static func coordinate(stops: [(latitude: Double, longitude: Double)],
                           currentIndex: Int) -> CLLocationCoordinate2D? {
        let ahead = stops.indices.filter { $0 >= currentIndex }
        let behind = stops.indices.filter { $0 < currentIndex }.reversed()
        for index in ahead + behind {
            let stop = stops[index]
            // 0, 0 is a stop never placed on the map.
            guard stop.latitude != 0 || stop.longitude != 0 else { continue }
            let coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
            if CLLocationCoordinate2DIsValid(coordinate) { return coordinate }
        }
        return nil
    }
}
