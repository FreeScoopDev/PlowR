import Foundation
import MapKit
import Testing
@testable import PlowR

/// A business found by the client side's search, as it's shown and sent.
@MainActor
struct BusinessResultTests {
    @Test func aBusinessKeepsItsNamePhoneAndPlace() {
        let item = MKMapItem(location: CLLocation(latitude: 44.5, longitude: -79.5),
                             address: MKAddress(fullAddress: "12 Main St, Springfield, IL 62701", shortAddress: "12 Main St"))
        item.name = "North Plow"
        item.phoneNumber = "555-0100"
        let result = BusinessResult.from(item)
        #expect(result.name == "North Plow" && result.phone == "555-0100")
        #expect(result.latitude == 44.5 && result.longitude == -79.5)
        #expect(!result.address.isEmpty)
    }

    @Test func noAddressIsEmptyNotMadeUp() {
        let item = MKMapItem(location: CLLocation(latitude: 44.5, longitude: -79.5), address: nil)
        #expect(BusinessResult.from(item).address == "")
    }
}
