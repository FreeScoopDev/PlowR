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

    // "Other" is the picker's entry for a typed reason. A service or saved
    // reason with that name, listed too, would save an empty reason.
    @Test func otherIsNeverAListedReason() {
        let services = [service("Other")]
        #expect(!AddVisitView.reasonPresets(services: services, operatorID: "op", saved: ["Other"]).contains("Other"))
    }

    @Test func twoServicesWithOneNameAreListedOnce() {
        let services = [service("Mowing", order: 0), service("Mowing", order: 1)]
        #expect(AddVisitView.reasonPresets(services: services, operatorID: "op", saved: [])
            == ["Mowing", "Inspection", "Routine Visit"])
    }

    // Editing a visit: a listed reason is picked; one that isn't any more
    // (a service since turned off, a typed reason) shows as Other, text kept.
    @Test func aVisitsReasonShowsAsPickedOrOther() {
        let presets = ["Lawn Mowing", "Inspection"]
        #expect(AddVisitView.pickerSelection(for: "Lawn Mowing", presets: presets) == ("Lawn Mowing", ""))
        #expect(AddVisitView.pickerSelection(for: "Snow Plowing", presets: presets) == ("Other", "Snow Plowing"))
        #expect(AddVisitView.pickerSelection(for: "", presets: presets) == ("", ""))
        #expect(AddVisitView.pickerSelection(for: "Other", presets: presets) == ("Other", "Other"))
    }

    // Saving "Other" as a preset would leave the visit with no reason: Other
    // is the picker's own entry, never a listed one.
    @Test func onlyANewNamedReasonCanBeSavedAsAPreset() {
        let presets = ["Lawn Mowing", "Inspection"]
        #expect(AddVisitView.canSaveAsPreset("Gutters", presets: presets))
        #expect(!AddVisitView.canSaveAsPreset("Other", presets: presets))
        #expect(!AddVisitView.canSaveAsPreset("Inspection", presets: presets))
        #expect(!AddVisitView.canSaveAsPreset("", presets: presets))
        #expect(!AddVisitView.canSaveAsPreset("   ", presets: presets))
        #expect(!AddVisitView.canSaveAsPreset("Inspection ", presets: presets))
        #expect(AddVisitView.presetName(" Gutters ") == "Gutters")
    }

    // A saved reason that's also a service, or empty, is listed once or not at all.
    @Test func savedReasonsComeLastWithoutRepeats() {
        let services = [service("Lawn Mowing")]
        #expect(AddVisitView.reasonPresets(services: services, operatorID: "op", saved: ["Lawn Mowing", "Gutters", ""])
            == ["Lawn Mowing", "Inspection", "Routine Visit", "Gutters"])
    }
}
