//
//  CoordinateBoundsTests.swift
//  PlowRTests
//

import Testing
import CoreLocation
import MapKit
@testable import PlowR

// CoordinateBounds replaced three hand-written min/max calculations (route map,
// route recap map, proposal PDF minimap). These pin the arithmetic those used,
// so the map framing can't change without a test noticing.
struct CoordinateBoundsTests {

    @Test func noPointsHasNoBounds() {
        #expect(CoordinateBounds([]) == nil)
        #expect(CoordinateBounds(latitudes: [], longitudes: []) == nil)
    }

    @Test func boundsAreTheMinAndMaxOfEachAxis() throws {
        let b = try #require(CoordinateBounds([
            CLLocationCoordinate2D(latitude: 43.10, longitude: -76.20),
            CLLocationCoordinate2D(latitude: 43.00, longitude: -76.00),
            CLLocationCoordinate2D(latitude: 43.05, longitude: -76.10),
        ]))
        #expect(b.minLatitude == 43.00)
        #expect(b.maxLatitude == 43.10)
        #expect(b.minLongitude == -76.20)
        #expect(b.maxLongitude == -76.00)
    }

    // The screens' formula: centre is the midpoint; span is 1.7 × the box.
    @Test func regionIsCentredAndPaddedBySevenTenths() throws {
        let b = try #require(CoordinateBounds(latitudes: [43.0, 43.1], longitudes: [-76.2, -76.0]))
        let r = b.region()
        #expect(abs(r.center.latitude - 43.05) < 1e-9)
        #expect(abs(r.center.longitude - (-76.1)) < 1e-9)
        #expect(abs(r.span.latitudeDelta - 0.1 * 1.7) < 1e-9)
        #expect(abs(r.span.longitudeDelta - 0.2 * 1.7) < 1e-9)
    }

    // Two stops on the same street must not zoom to rooftop level.
    @Test func tinyBoxesAreWidenedToTheMinimum() throws {
        let b = try #require(CoordinateBounds(latitudes: [43.0, 43.0001], longitudes: [-76.0, -76.0]))
        let r = b.region()
        #expect(r.span.latitudeDelta == 0.006)
        #expect(r.span.longitudeDelta == 0.006)
    }
}
