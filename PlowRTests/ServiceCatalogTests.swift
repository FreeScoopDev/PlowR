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
        #expect(added.map(\.pricePerUnit) == [0.06, 30, 0.04, 60])
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

    // Asked for again, only the missing ones come back, after the rest.
    @Test func askingAgainAddsOnlyWhatsMissingAfterTheRest() throws {
        let mine = [service("Lawn Mowing", category: "lawn", order: 3), service("Patio", category: "custom", order: 999)]
        let added = ServiceCatalog.addStandard(lawn, operatorID: "op", existing: mine, to: context)
        #expect(added.map(\.name) == ["Edging", "Fertilization", "Hedge Trimming"])
        #expect(added.map(\.sortOrder) == [1000, 1001, 1002])
    }

    @Test func anotherBusinessesServicesDontCount() throws {
        let theirs = [service("Lawn Mowing", category: "lawn", operatorID: "someone-else")]
        #expect(ServiceCatalog.offered(from: theirs, operatorID: "op").map(\.key) == ["snow", "lawn", "cleanup"])
        let added = ServiceCatalog.addStandard(lawn, operatorID: "op", existing: theirs, to: context)
        #expect(added.count == 4)
        #expect(added.first?.sortOrder == 0)
    }

    @Test func everyStandardServiceIsInAnOfferedCategory() {
        let keys = Set(ServiceCatalog.standardCategories.map(\.key))
        #expect(ServiceItem.defaultServices.allSatisfy { keys.contains($0.category) })
    }
}
