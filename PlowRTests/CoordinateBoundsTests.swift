//
//  CoordinateBoundsTests.swift
//  PlowRTests
//

import Testing
import CoreLocation
import MapKit
@testable import PlowR

// CoordinateBounds replaced four hand-written min/max calculations (route map,
// route recap map, client property map, proposal PDF minimap). These pin its
// arithmetic and its defaults. They don't pin which padding each screen passes;
// that is one line at each call site.
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

    // The client property map's framing: 3.5× the zones' box, floor 0.0005°.
    @Test func customPaddingAndMinimumAreApplied() throws {
        let b = try #require(CoordinateBounds(latitudes: [43.0, 43.001], longitudes: [-76.0, -76.00001]))
        let r = b.region(padding: 3.5, minimumDelta: 0.0005)
        #expect(abs(r.span.latitudeDelta - 0.001 * 3.5) < 1e-9)
        #expect(r.span.longitudeDelta == 0.0005)
    }

    // Two stops on the same street must not zoom to rooftop level.
    @Test func tinyBoxesAreWidenedToTheMinimum() throws {
        let b = try #require(CoordinateBounds(latitudes: [43.0, 43.0001], longitudes: [-76.0, -76.0]))
        let r = b.region()
        #expect(r.span.latitudeDelta == 0.006)
        #expect(r.span.longitudeDelta == 0.006)
    }
}
