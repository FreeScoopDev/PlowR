//
//  ContractsTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Contracts: where one stands, what it says, and making, signing,
/// cancelling and deleting one.
@MainActor
struct ContractsTests {
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func contract(_ h: Harness, pricing: Contracts.Pricing = .season, price: String = "900",
                          installments: Int = 3) -> Contract {
        var draft = Contracts.Draft(for: h.client, now: h.clock)
        draft.pricing = pricing
        draft.priceText = price
        draft.installments = installments
        return Contracts.save(draft, to: nil, of: h.client, in: h.context)
    }

    @Test func aNewContractIsADraftForSixMonthsAtTheirOwnAddress() throws {
        let h = try Harness(stopCount: 0)
        h.client.expectedServiceIDs = ["plow", "walks"]
        let draft = Contracts.Draft(for: h.client, now: h.clock)
        #expect(draft.placeIDs == [h.client.id.uuidString])
        #expect(draft.serviceIDs == ["plow", "walks"])
        #expect(draft.problem(now: h.clock) == "Enter its price.")
        let saved = contract(h)
        #expect(saved.client?.id == h.client.id)
        #expect(Contracts.status(of: saved, now: h.clock) == .draft)
        #expect(saved.serviceIDs == ["plow", "walks"])
        #expect(saved.name.contains("–"))                                          // named for its dates
        #expect(saved.clientID == h.client.id.uuidString && saved.clientName == h.client.name)
        var calendar = Calendar.current
        calendar.timeZone = .current
        #expect(saved.endDate == calendar.date(byAdding: DateComponents(month: 6, day: -1), to: calendar.startOfDay(for: h.clock)))
        #expect(h.client.contracts?.count == 1)
    }

    @Test func whatStopsItBeingSaved() throws {
        let h = try Harness(stopCount: 0)
        var draft = Contracts.Draft(for: h.client, now: h.clock)
        draft.priceText = "100"
        #expect(draft.problem(now: h.clock) == "Choose the services it covers.")
        draft.serviceIDs = ["plow"]
        #expect(draft.problem(now: h.clock) == nil)
        draft.placeIDs = []
        #expect(draft.problem(now: h.clock) == "Choose where it applies.")
        draft.placeIDs = [h.client.id.uuidString]
        draft.endDate = draft.startDate.addingTimeInterval(-day)
        #expect(draft.problem(now: h.clock) == "It has to end after it starts.")
    }

    @Test func onlyASeasonPriceHasInstallments() throws {
        let h = try Harness(stopCount: 0)
        #expect(contract(h, pricing: .season, installments: 3).installments == 3)
        #expect(contract(h, pricing: .monthly, price: "160", installments: 3).installments == 1)
        #expect(Contracts.priceSummary(of: contract(h, pricing: .season, installments: 3)) == "$900.00 season, 3 payments")
        #expect(Contracts.priceSummary(of: contract(h, pricing: .season, installments: 1)) == "$900.00 season")
        #expect(Contracts.priceSummary(of: contract(h, pricing: .perVisit, price: "55")) == "$55.00 per visit")
        #expect(Contracts.priceSummary(of: contract(h, pricing: .monthly, price: "160")) == "$160.00 a month")
    }

    @Test func aContractStandsFromSigningThroughItsLastDay() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h)
        season.startDate = h.clock.addingTimeInterval(10 * day)
        season.endDate = h.clock.addingTimeInterval(40 * day)
        Contracts.sign(season, in: h.context, now: h.clock)
        #expect(Contracts.status(of: season, now: h.clock) == .upcoming)
        #expect(Contracts.status(of: season, now: Calendar.current.startOfDay(for: season.startDate).addingTimeInterval(-3_600)) == .upcoming)
        #expect(Contracts.status(of: season, now: season.startDate) == .active)
        #expect(Contracts.status(of: season, now: season.endDate.addingTimeInterval(3_600)) == .active)
        #expect(Contracts.status(of: season, now: season.endDate.addingTimeInterval(day)) == .ended)
        Contracts.cancel(season, in: h.context, now: h.clock)
        #expect(Contracts.status(of: season, now: h.clock) == .cancelled)
    }

    // Signed, the client is a customer; a draft or a cancelled one doesn't make them one.
    @Test func aSignedContractMakesThemACustomer() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h)
        let facts = Pipeline.Facts(in: h.context)
        #expect(Pipeline.stage(of: h.client, facts: facts, now: h.clock) == .lead)
        Contracts.sign(season, in: h.context, now: h.clock)
        #expect(Contracts.hasContractInForce(h.client, now: h.clock))
        #expect(Pipeline.stage(of: h.client, facts: facts, now: h.clock) == .customer)
        #expect(Pipeline.stage(of: h.client, facts: facts, now: h.clock.addingTimeInterval(200 * day)) == .lead) // ended
        Contracts.cancel(season, in: h.context, now: h.clock)
        #expect(Pipeline.stage(of: h.client, facts: facts, now: h.clock) == .lead)
    }

    @Test func onlyADraftCanBeDeleted() throws {
        let h = try Harness(stopCount: 0)
        let signed = contract(h)
        Contracts.sign(signed, in: h.context, now: h.clock)
        Contracts.deleteDraft(signed, in: h.context)
        #expect(signed.modelContext != nil && !signed.isDeleted)
        let draft = contract(h)
        Contracts.deleteDraft(draft, in: h.context)
        #expect(try h.context.fetch(FetchDescriptor<Contract>()).map(\.id) == [signed.id])
    }

    @Test func theOnesInForceComeFirst() throws {
        let h = try Harness(stopCount: 0)
        let old = contract(h)
        old.startDate = h.clock.addingTimeInterval(-400 * day)
        old.endDate = h.clock.addingTimeInterval(-200 * day)
        Contracts.sign(old, in: h.context, now: h.clock)
        let newDraft = contract(h)
        newDraft.startDate = h.clock.addingTimeInterval(30 * day)
        let current = contract(h)
        current.startDate = h.clock.addingTimeInterval(-10 * day)
        Contracts.sign(current, in: h.context, now: h.clock)
        #expect(Contracts.sorted([old, newDraft, current], now: h.clock).map(\.id) == [current.id, newDraft.id, old.id])
    }

    // Keep Records keeps signed contracts, as it does invoices; a draft
    // goes. Delete Everything deletes them all.
    @Test func deletingAClientKeepsSignedContractsWithKeepRecords() throws {
        let h = try Harness(stopCount: 0)
        let signed = contract(h)
        Contracts.sign(signed, in: h.context, now: h.clock)
        _ = contract(h)
        try h.context.save()
        let footprint = ClientRemoval.footprint(of: h.client, in: h.context)
        #expect(footprint.contracts == 1)
        #expect(ClientRemoval.deleteMessage(for: footprint, isActive: false).contains("1 signed contract"))
        let name = h.client.name
        ClientRemoval.delete(h.client, keepingRecords: true, in: h.context)
        let kept = try h.context.fetch(FetchDescriptor<Contract>())
        #expect(kept.map(\.id) == [signed.id])
        #expect(kept.first?.client == nil && kept.first?.clientName == name)
    }

    @Test func deletingEverythingDeletesTheirContracts() throws {
        let h = try Harness(stopCount: 0)
        Contracts.sign(contract(h), in: h.context, now: h.clock)
        try h.context.save()
        ClientRemoval.delete(h.client, keepingRecords: false, in: h.context)
        #expect(try h.context.fetch(FetchDescriptor<Contract>()).isEmpty)
    }

    // Signed, what was agreed is locked; the name, notes and end date (not
    // before today) can change.
    @Test func aSignedContractsTermsAreLocked() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h)
        Contracts.sign(season, in: h.context, now: h.clock)
        var draft = Contracts.Draft(season)
        #expect(draft.isSigned)
        draft.priceText = "1"
        draft.pricing = .monthly
        draft.serviceIDs = ["other"]
        draft.startDate = h.clock.addingTimeInterval(-90 * day)
        draft.notes = "Gate code 1234"
        draft.endDate = season.endDate.addingTimeInterval(30 * day)
        Contracts.save(draft, to: season, of: h.client, in: h.context)
        #expect(season.price == 900 && Contracts.pricing(of: season) == .season && season.installments == 3)
        #expect(season.serviceIDs.isEmpty && season.startDate != draft.startDate)
        #expect(season.notes == "Gate code 1234" && season.endDate == draft.endDate)
        draft.endDate = h.clock.addingTimeInterval(-day)
        #expect(draft.problem(now: h.clock) == "A signed contract can't end before today. To end it now, cancel it.")
        #expect(draft.earliestEnd(now: h.clock) >= Calendar.current.startOfDay(for: h.clock))
    }

    // A removed property is dropped from the contract's places when it's
    // edited, so it has to be set to apply somewhere real.
    @Test func aRemovedPropertyIsDroppedFromItsPlaces() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h)
        season.placeIDs = [UUID().uuidString]
        #expect(Contracts.Draft(season).problem(now: h.clock) == "Choose where it applies.")
    }

    @Test func onlyASnowContractKeepsATrigger() throws {
        let h = try Harness(stopCount: 0)
        let plow = ServiceItem(name: "Plowing", category: "snow", unitType: "flat", pricePerUnit: 50, operatorID: "op")
        let mow = ServiceItem(name: "Mowing", category: "lawn", unitType: "flat", pricePerUnit: 40, operatorID: "op")
        [plow, mow].forEach { h.context.insert($0) }
        var draft = Contracts.Draft(for: h.client, now: h.clock)
        draft.priceText = "900"
        draft.triggerInches = 2
        draft.serviceIDs = [plow.id.uuidString]
        #expect(Contracts.save(draft, to: nil, of: h.client, in: h.context).triggerInches == 2)
        draft.serviceIDs = [mow.id.uuidString]
        #expect(Contracts.save(draft, to: nil, of: h.client, in: h.context).triggerInches == 0)
    }

    // Named for its dates, it's named again when they change.
    @Test func aNameMadeFromItsDatesFollowsThem() throws {
        let h = try Harness(stopCount: 0)
        let season = contract(h)
        var draft = Contracts.Draft(season)
        #expect(draft.name.isEmpty)
        draft.endDate = season.endDate.addingTimeInterval(400 * day)
        Contracts.save(draft, to: season, of: h.client, in: h.context)
        #expect(season.name == Contracts.name(from: season.startDate, to: draft.endDate))
        draft.name = "Winter"
        Contracts.save(draft, to: season, of: h.client, in: h.context)
        #expect(Contracts.Draft(season).name == "Winter")
    }
}
