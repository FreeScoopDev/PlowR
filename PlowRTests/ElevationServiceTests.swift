//
//  ElevationServiceTests.swift
//  PlowRTests
//

import Testing
import Foundation
import CoreLocation
@testable import PlowR

/// Terrain lookups for property zones. The host used to be a domain that
/// doesn't exist, and each zone was its own request against an API that allows
/// one a second. No test here touches the network: requests go to a fake.
struct ElevationServiceTests {

    private typealias Coord = CLLocationCoordinate2D

    /// Records requests and answers each location with an elevation from `height`.
    private actor FakeAPI {
        var requests: [URL] = []
        var status = 200
        let height: @Sendable (Double, Double) -> Double?
        init(height: @escaping @Sendable (Double, Double) -> Double?) { self.height = height }

        func setStatus(_ code: Int) { status = code }

        func answer(_ url: URL) throws -> (Data, URLResponse) {
            requests.append(url)
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "locations" }?.value ?? ""
            let results: [[String: Any]] = value.split(separator: "|").map { pair in
                let parts = pair.split(separator: ",").compactMap { Double($0) }
                let elevation: Any = height(parts[0], parts[1]).map { $0 as Any } ?? NSNull()
                return ["elevation": elevation]
            }
            let body = try JSONSerialization.data(withJSONObject: ["results": results, "status": "OK"])
            return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func service(_ api: FakeAPI) -> ElevationService {
        ElevationService(fetch: { try await api.answer($0) }, pause: .zero)
    }

    /// Three corners running about 100 m north from (43, -72).
    private let slopeZone = [Coord(latitude: 43, longitude: -72),
                             Coord(latitude: 43.00045, longitude: -72),
                             Coord(latitude: 43.0009, longitude: -72)]
    private let flatZone = [Coord(latitude: 44, longitude: -72),
                            Coord(latitude: 44.0009, longitude: -72)]

    @Test func requestsGoToTheRealOpenTopoDataHost() throws {
        let url = try #require(ElevationService.requestURL(for: [Coord(latitude: 43.5, longitude: -72.25),
                                                                 Coord(latitude: 43.6, longitude: -72.35)]))
        #expect(url.host == "api.opentopodata.org")
        #expect(url.path == "/v1/srtm30m")
        let locations = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "locations" }?.value
        #expect(locations == "43.5,-72.25|43.6,-72.35")
    }

    // Every zone of a property in one request, each zone's grade from its own points.
    @Test func allZonesAreLookedUpInOneRequest() async {
        let api = FakeAPI { lat, _ in lat >= 43.0009 && lat < 43.001 ? 10 : (lat >= 44 ? 5 : 0) }
        let grades = await service(api).fetchGrades(for: [slopeZone, flatZone])
        #expect(await api.requests.count == 1)
        #expect(grades.count == 2)
        let slope = try? #require(grades[0])
        #expect(slope.map { abs($0 - 10) < 0.5 } == true)    // 10 m rise over ~100 m
        #expect(grades[1] == 0)
    }

    // 100 locations per request at most: 34 zones × 3 points needs a second request.
    @Test func largePropertiesAreSplitIntoRequestsOfAtMostAHundredPoints() async {
        let api = FakeAPI { _, _ in 5 }
        let zones = Array(repeating: flatZone, count: 34)
        let grades = await service(api).fetchGrades(for: zones)
        let requests = await api.requests
        #expect(requests.count == 2)
        for url in requests {
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "locations" }?.value ?? ""
            #expect(value.split(separator: "|").count <= 100)
        }
        #expect(grades.count == 34)
        #expect(grades.allSatisfy { $0 == 0 })
    }

    // The API answers null where it has no data. Decoding the elevation as a
    // plain number failed the whole lookup on one null.
    @Test func aNullElevationDoesNotSpoilTheLookup() async {
        let api = FakeAPI { lat, _ in lat == 43.00045 ? nil : (lat >= 43.0009 ? 10 : 0) }
        let grade = await service(api).fetchGrade(for: slopeZone)
        #expect(grade.map { abs($0 - 10) < 0.5 } == true)
    }

    // A failed lookup is "unknown" (nil), never "flat", so a zone keeps the grade it had.
    @Test func aFailedLookupIsUnknownNotFlat() async {
        let api = FakeAPI { _, _ in 5 }
        await api.setStatus(429)
        #expect(await service(api).fetchGrades(for: [slopeZone, flatZone]) == [nil, nil])

        let offline = ElevationService(fetch: { _ in throw URLError(.notConnectedToInternet) }, pause: .zero)
        #expect(await offline.fetchGrade(for: slopeZone) == nil)
    }

    // The API returns null where it has no data; one null used to fail the whole lookup.
    @Test func aPointWithNoDataIsSkipped() {
        #expect(ElevationService.grade(samples: slopeZone, elevations: [0, nil, 10]).map { abs($0 - 10) < 0.5 } == true)
        #expect(ElevationService.grade(samples: slopeZone, elevations: [nil, nil, 10]) == nil)
        #expect(ElevationService.grade(samples: slopeZone, elevations: [7, 7, 7]) == 0)
    }

    @Test func aZoneIsSampledAtItsStartMiddleAndEnd() {
        let corners = (0..<4).map { Coord(latitude: 43 + Double($0), longitude: -72) }
        #expect(ElevationService.samplePoints(corners).map(\.latitude) == [43, 45, 46])
        #expect(ElevationService.samplePoints([corners[0]]).isEmpty)
    }
}

/// The property map's edit mode, after a zone is deleted from the list.
struct ZoneEditingIndexTests {

    // Editing the last of three zones, delete the first: the edited zone is now at 1.
    // Keeping index 2 pointed past the end, and the next map tap crashed.
    @Test func deletingAnEarlierZoneShiftsTheEditedOne() {
        #expect(PropertyScannerView.editingIndex(afterDeleting: 0, editing: 2) == 1)
    }

    @Test func deletingTheEditedZoneEndsEditing() {
        #expect(PropertyScannerView.editingIndex(afterDeleting: 2, editing: 2) == nil)
    }

    @Test func deletingALaterZoneLeavesTheEditedOneAlone() {
        #expect(PropertyScannerView.editingIndex(afterDeleting: 3, editing: 1) == 1)
        #expect(PropertyScannerView.editingIndex(afterDeleting: 0, editing: nil) == nil)
    }
}
