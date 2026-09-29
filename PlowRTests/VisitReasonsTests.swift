//
//  VisitReasonsTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// The reasons Add Visit offers. They were four snow services plus
/// "Inspection" and "Routine Visit", whatever the business did.
@MainActor
struct VisitReasonsTests {
    private func service(_ name: String, operatorID: String = "op", order: Int = 0, active: Bool = true) -> ServiceItem {
        let s = ServiceItem(name: name, category: "lawn", unitType: "flat", pricePerUnit: 10, operatorID: operatorID,
                            sortOrder: order)
        s.isActive = active
        return s
    }

    @Test func aLawnBusinessIsOfferedItsOwnServices() {
        let services = [service("Edging", order: 1), service("Lawn Mowing", order: 0)]
        #expect(AddVisitView.reasonPresets(services: services, operatorID: "op", saved: [])
            == ["Lawn Mowing", "Edging", "Inspection", "Routine Visit"])
    }

    @Test func withNoServicesTheGeneralReasonsAreLeft() {
        #expect(AddVisitView.reasonPresets(services: [], operatorID: "op", saved: []) == ["Inspection", "Routine Visit"])
    }

    @Test func turnedOffAndOtherBusinessesServicesArentOffered() {
        let services = [service("Mulching", active: false), service("Theirs", operatorID: "someone-else")]
        #expect(AddVisitView.reasonPresets(services: services, operatorID: "op", saved: []) == ["Inspection", "Routine Visit"])
    }

    // A saved reason that's also a service, or empty, is listed once or not at all.
    @Test func savedReasonsComeLastWithoutRepeats() {
        let services = [service("Lawn Mowing")]
        #expect(AddVisitView.reasonPresets(services: services, operatorID: "op", saved: ["Lawn Mowing", "Gutters", ""])
            == ["Lawn Mowing", "Inspection", "Routine Visit", "Gutters"])
    }
}
