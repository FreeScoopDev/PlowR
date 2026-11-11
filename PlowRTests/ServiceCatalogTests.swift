//
//  ServiceCatalogTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The standard services are offered and added only when asked. They were
/// added whenever Settings > Service Catalog opened: deleted ones came back,
/// and a second device added a second set before the first one's arrived.
@MainActor
struct ServiceCatalogTests {
    private let lawn = ServiceCatalog.Category(key: "lawn", label: "Lawn Care")
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
    }

    private func service(_ name: String, category: String, operatorID: String = "op", order: Int = 0) -> ServiceItem {
        ServiceItem(name: name, category: category, unitType: "flat", pricePerUnit: 10, operatorID: operatorID,
                    sortOrder: order)
    }

    @Test func aNewBusinessIsOfferedEveryStandardCategory() {
        #expect(ServiceCatalog.offered(from: [], operatorID: "op").map(\.key) == ["snow", "lawn", "cleanup"])
    }

    @Test func addingACategoryAddsItsStandardServices() throws {
        let added = ServiceCatalog.addStandard(lawn, operatorID: "op", existing: [], to: context)
        #expect(added.map(\.name) == ["Lawn Mowing", "Edging", "Fertilization", "Hedge Trimming"])
        #expect(added.map(\.pricePerUnit) == [45, 30, 60, 60])
        #expect(added.allSatisfy { $0.unitType == "flat" })
        #expect(added.allSatisfy { $0.operatorID == "op" && $0.isBuiltIn && $0.category == "lawn" && $0.isActive })
        #expect(try context.fetchCount(FetchDescriptor<ServiceItem>()) == 4)
        #expect(ServiceCatalog.offered(from: added, operatorID: "op").map(\.key) == ["snow", "cleanup"])
    }

    @Test func askingTwiceAddsNothingMore() throws {
        let first = ServiceCatalog.addStandard(lawn, operatorID: "op", existing: [], to: context)
        #expect(ServiceCatalog.addStandard(lawn, operatorID: "op", existing: first, to: context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<ServiceItem>()) == 4)
    }

    // Deleted from the catalog, a standard service stays deleted: the
    // category isn't offered again while it has services.
    @Test func aDeletedStandardServiceIsntAddedBack() {
        let left = [service("Lawn Mowing", category: "lawn"), service("Hedge Trimming", category: "lawn")]
        #expect(!ServiceCatalog.offered(from: left, operatorID: "op").contains { $0.key == "lawn" })
    }

    // A custom service with a standard service's name isn't added twice, and
    // the standard ones go after the business's own.
    @Test func aCustomServiceWithAStandardNameIsntDoubled() throws {
        let mine = [service("Edging", category: "custom", order: 999)]
        let added = ServiceCatalog.addStandard(lawn, operatorID: "op", existing: mine, to: context)
        #expect(added.map(\.name) == ["Lawn Mowing", "Fertilization", "Hedge Trimming"])
        #expect(added.map(\.sortOrder) == [1000, 1001, 1002])
    }

    @Test func anotherBusinessesServicesDontCount() throws {
        let theirs = [service("Lawn Mowing", category: "lawn", operatorID: "someone-else")]
        #expect(ServiceCatalog.offered(from: theirs, operatorID: "op").map(\.key) == ["snow", "lawn", "cleanup"])
        let added = ServiceCatalog.addStandard(lawn, operatorID: "op", existing: theirs, to: context)
        #expect(added.count == 4)
        #expect(added.first?.sortOrder == 0)
    }

    // An empty catalog offers the standard services where they'd be listed;
    // one with every service turned off says so instead.
    @Test func whatABusinessHasToPickFrom() {
        let off = service("Patio", category: "custom")
        off.isActive = false
        #expect(ServiceCatalog.coverage(of: [], operatorID: "op") == .empty)
        #expect(ServiceCatalog.coverage(of: [service("Theirs", category: "lawn", operatorID: "x")], operatorID: "op") == .empty)
        #expect(ServiceCatalog.coverage(of: [off], operatorID: "op") == .allOff)
        #expect(ServiceCatalog.coverage(of: [off, service("Mowing", category: "lawn")], operatorID: "op") == .some)
    }

    /// The starter catalog is flat, at placeholder prices the business edits:
    /// per square foot recorded $0 wherever no area was measured (Joe,
    /// 2026-11-10). Per square foot stays a choice in Add Service.
    @Test func theStarterCatalogIsFlat() {
        let starter = ServiceItem.defaultServices.map { "\($0.name)|\($0.unitType)|\($0.price)" }
        #expect(starter == [
            "Snow Plowing|flat|50.0", "Salting / Ice Melt|flat|25.0", "Walkway Shoveling|flat|45.0",
            "Roof Snow Removal|flat|150.0", "Lawn Mowing|flat|45.0", "Edging|flat|30.0",
            "Fertilization|flat|60.0", "Hedge Trimming|flat|60.0", "Spring Cleanup|flat|120.0",
            "Fall Cleanup|flat|120.0", "Mulching|flat|75.0",
        ])
        // And what a business adds from it is the same.
        let added = ServiceCatalog.standardCategories.flatMap {
            ServiceCatalog.addStandard($0, operatorID: "op", existing: [], to: context)
        }
        #expect(added.count == ServiceItem.defaultServices.count)
        #expect(added.allSatisfy { $0.unitType == "flat" && $0.pricePerUnit > 0 })
    }

    @Test func everyStandardServiceIsInAnOfferedCategory() {
        let keys = Set(ServiceCatalog.standardCategories.map(\.key))
        #expect(ServiceItem.defaultServices.allSatisfy { keys.contains($0.category) })
    }
}
