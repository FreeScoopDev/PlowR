//
//  ContractBillingTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Work under a contract: covered by a season or monthly one, priced by a
/// per-visit one, extras billed as usual.
@MainActor
struct ContractBillingTests {
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func signed(_ h: Harness, _ pricing: Contracts.Pricing, price: String, services: [String],
                        places: Set<String>? = nil) -> Contract {
        var draft = Contracts.Draft(for: h.client, now: h.clock.addingTimeInterval(-10 * day))
        draft.pricing = pricing
        draft.priceText = price
        draft.serviceIDs = Set(services)
        if let places { draft.placeIDs = places }
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        Contracts.sign(contract, in: h.context, now: h.clock.addingTimeInterval(-10 * day))
        return contract
    }

    private func job(_ h: Harness, _ lines: [(String, Double)], daysAgo: Double = 1, propertyID: String? = nil)
        -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: "manual:\(UUID().uuidString)", source: .manual)
        record.clientID = h.client.id.uuidString
        record.propertyID = propertyID ?? h.client.id.uuidString
        record.performedAt = h.clock.addingTimeInterval(-daysAgo * day)
        record.lines = lines.map { .init(serviceID: $0.0, name: $0.0.capitalized, unitType: "flat", price: $0.1) }
        h.context.insert(record)
        return record
    }

    @Test func aContractCoversItsPlacesFromItsStartUntilCancelled() throws {
        let h = try Harness(stopCount: 0)
        let season = signed(h, .season, price: "900", services: ["plow"])
        let main = h.client.id.uuidString
        #expect(Contracts.covers(season, placeID: main, on: h.clock))
        #expect(!Contracts.covers(season, placeID: main, on: h.clock.addingTimeInterval(-11 * day)))   // before it
        #expect(!Contracts.covers(season, placeID: UUID().uuidString, on: h.clock))                    // not its place
        #expect(!Contracts.covers(season, placeID: main, on: season.endDate.addingTimeInterval(day)))  // after it
        Contracts.cancel(season, in: h.context, now: h.clock)
        #expect(Contracts.covers(season, placeID: main, on: h.clock))                                  // the day it ended
        #expect(!Contracts.covers(season, placeID: main, on: h.clock.addingTimeInterval(day)))
        let draft = Contracts.save(Contracts.Draft(for: h.client, now: h.clock), to: nil, of: h.client, in: h.context)
        #expect(!Contracts.covers(draft, placeID: main, on: h.clock))                                  // not signed
    }

    @Test func aSeasonContractCoversItsServicesAndBillsExtras() throws {
        let h = try Harness(stopCount: 0)
        let contracts = [signed(h, .season, price: "900", services: ["plow"])]
        let plowed = job(h, [("plow", 60)])
        let plowedAndSalted = job(h, [("plow", 60), ("salt", 25)])
        let before = job(h, [("plow", 60)], daysAgo: 30)                          // before the contract
        #expect(ServiceLog.charge(of: plowed, contracts: contracts).isEmpty)
        #expect(ServiceLog.isCovered(plowed, contracts: contracts))
        #expect(ServiceLog.charge(of: plowedAndSalted, contracts: contracts).map(\.serviceID) == ["salt"])
        #expect(!ServiceLog.isCovered(plowedAndSalted, contracts: contracts))
        #expect(ServiceLog.charge(of: before, contracts: contracts).map(\.price) == [60])
        #expect(ServiceLog.billingStatus(of: plowed, in: h.context) == .covered)
        #expect(ServiceLog.billingStatus(of: plowedAndSalted, in: h.context) == .notBilled)
        #expect(plowed.lines.map(\.price) == [60])                                // what was done stays recorded
    }

    @Test func aPerVisitContractIsOneLineAtItsPrice() throws {
        let h = try Harness(stopCount: 0)
        let contract = signed(h, .perVisit, price: "55", services: ["plow", "walks"])
        let visit = job(h, [("plow", 60), ("walks", 20), ("salt", 25)])
        let charge = ServiceLog.charge(of: visit, contracts: [contract])
        #expect(charge.map(\.price) == [55, 25])
        #expect(charge.first?.name == "\(contract.name): visit")
        #expect(!ServiceLog.isCovered(visit, contracts: [contract]))
        let notCovered = job(h, [("salt", 25)])
        #expect(ServiceLog.charge(of: notCovered, contracts: [contract]).map(\.price) == [25])
    }

    @Test func aContractCoversOnlyThePlacesItNames() throws {
        let h = try Harness(stopCount: 0)
        let rental = Property(label: "Rental", address: "9 Elm St", operatorID: "op")
        h.context.insert(rental)
        rental.client = h.client
        let contracts = [signed(h, .monthly, price: "160", services: ["mow"], places: [rental.id.uuidString])]
        #expect(ServiceLog.isCovered(job(h, [("mow", 45)], propertyID: rental.id.uuidString), contracts: contracts))
        #expect(!ServiceLog.isCovered(job(h, [("mow", 45)]), contracts: contracts))  // their own address isn't
        // A job with no place saved is at their own address.
        let atHome = [signed(h, .season, price: "900", services: ["plow"])]
        #expect(ServiceLog.isCovered(job(h, [("plow", 60)], propertyID: ""), contracts: atHome))
    }

    // Bill Unbilled Work leaves covered jobs off, and bills a per-visit
    // contract's visits at its price.
    @Test func billingUnbilledWorkFollowsTheContracts() throws {
        let h = try Harness(stopCount: 0)
        _ = signed(h, .perVisit, price: "55", services: ["plow"])
        _ = job(h, [("plow", 60)])
        _ = job(h, [("plow", 60), ("salt", 25)])
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        #expect(work.records.count == 2)
        #expect(work.total == 135)                                                 // 55 + 55 + 25
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.sortedLineItems.map(\.lineTotal).sorted() == [25, 55, 55])
    }

    @Test func coveredWorkIsNotBilled() throws {
        let h = try Harness(stopCount: 0)
        _ = signed(h, .season, price: "900", services: ["plow"])
        _ = job(h, [("plow", 60)])
        #expect(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).isEmpty)
        let csv = CSVExport.serviceHistory(try h.context.fetch(FetchDescriptor<ServiceRecord>()), operatorID: "op",
                                           in: h.context)
        #expect(csv.contains("Covered by Contract"))
    }

    // A contract kept after its client was deleted still explains their past work.
    @Test func aKeptContractStillCoversTheWorkItCovered() throws {
        let h = try Harness(stopCount: 0)
        let season = signed(h, .season, price: "900", services: ["plow"])
        let plowed = job(h, [("plow", 60)])
        season.client = nil
        #expect(ServiceLog.isCovered(plowed, contracts: [season]))
    }

    // Record Services' own invoice follows the contract too.
    @Test func anInvoiceFromRecordServicesFollowsTheContract() throws {
        let h = try Harness(stopCount: 0)
        let services = [StopRecording.Service(id: "plow", name: "Plow", unitType: "flat", pricePerUnit: 60),
                        StopRecording.Service(id: "salt", name: "Salt", unitType: "flat", pricePerUnit: 25)]
        var recording = StopRecording(services: services, zones: [])
        recording.selectedIDs = ["plow"]
        let season = signed(h, .season, price: "900", services: ["plow"])
        #expect(recording.invoiceLines(under: season).isEmpty)                    // nothing to invoice
        #expect(recording.invoiceLines(under: nil).map(\.lineTotal) == [60])
        recording.selectedIDs = ["plow", "salt"]
        #expect(recording.invoiceLines(under: season).map(\.serviceName) == ["Salt"])
        let perVisit = signed(h, .perVisit, price: "55", services: ["plow"])
        #expect(recording.invoiceLines(under: perVisit).map(\.lineTotal) == [55, 25])
    }

    // A night route started on the contract's last day and finished after
    // midnight is that day's work.
    @Test func aJobIsCoveredByTheDayItStarted() throws {
        let h = try Harness(stopCount: 0)
        let season = signed(h, .season, price: "900", services: ["plow"])
        let lastDay = Calendar.current.startOfDay(for: season.endDate)
        let night = job(h, [("plow", 60)])
        night.startedAt = lastDay.addingTimeInterval(23.5 * 3_600)
        night.performedAt = lastDay.addingTimeInterval(24.5 * 3_600)
        #expect(ServiceLog.isCovered(night, contracts: [season]))
    }

    @Test func theNewestSignedContractCoversAnOverlap() throws {
        let h = try Harness(stopCount: 0)
        let older = signed(h, .perVisit, price: "50", services: ["plow"])
        let newer = signed(h, .perVisit, price: "65", services: ["plow"])
        newer.signedAt = h.clock.addingTimeInterval(-day)
        #expect(Contracts.contract(covering: job(h, [("plow", 60)]), among: [newer, older])?.id == newer.id)
        #expect(Contracts.contract(covering: job(h, [("plow", 60)]), among: [older, newer])?.id == newer.id)
    }

    // Invoiced, before the log, or no charge come before covered.
    @Test func coveredComesAfterTheOtherStates() throws {
        let h = try Harness(stopCount: 0)
        let record = job(h, [("plow", 60)])
        #expect(ServiceLog.billingStatus(of: record, invoiced: true, covered: true) == .invoiced)
        record.isBillable = false
        #expect(ServiceLog.billingStatus(of: record, invoiced: false, covered: true) == .noCharge)
        record.isBillable = true
        #expect(ServiceLog.billingStatus(of: record, invoiced: false, covered: true) == .covered)
        #expect(ServiceLog.billingStatus(of: record, invoiced: false, covered: false) == .notBilled)
    }
}
