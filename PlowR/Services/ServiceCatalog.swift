import Foundation
import SwiftData

/// The standard services a business can start its catalog with, offered one
/// category at a time and added only when the user asks.
///
/// They used to be added by themselves the first time Settings > Service
/// Catalog opened, and again whenever one was missing: a service the user
/// deleted came back, a business that went straight to a route had none, and
/// a second iPhone or iPad added its own set before the first device's
/// arrived through iCloud, so every standard service showed twice. And a lawn
/// business got snow services it never asked for.
enum ServiceCatalog {
    struct Category: Identifiable, Equatable {
        var key: String
        var label: String
        var id: String { key }
    }

    /// In the order the catalog lists them. Services the user adds are "custom".
    static let standardCategories = [
        Category(key: "snow", label: "Snow Removal"),
        Category(key: "lawn", label: "Lawn Care"),
        Category(key: "cleanup", label: "Cleanup")
    ]
    static let custom = Category(key: "custom", label: "Custom Services")

    /// What a business has to pick from.
    enum Coverage: Equatable {
        /// No services at all: offer the standard ones.
        case none
        /// Services, all turned off in the catalog.
        case allOff
        case some
    }

    static func coverage(of services: [ServiceItem], operatorID: String) -> Coverage {
        let mine = services.filter { $0.operatorID == operatorID }
        if mine.isEmpty { return .none }
        return mine.contains(where: \.isActive) ? .some : .allOff
    }

    /// The standard categories to offer: those this business has no service in.
    static func offered(from services: [ServiceItem], operatorID: String) -> [Category] {
        let used = Set(services.filter { $0.operatorID == operatorID }.map(\.category))
        return standardCategories.filter { !used.contains($0.key) }
    }

    /// Adds `category`'s standard services that this business doesn't have
    /// yet, by name, after its other services. Returns what it added.
    @discardableResult
    static func addStandard(_ category: Category, operatorID: String, existing: [ServiceItem],
                            to context: ModelContext) -> [ServiceItem] {
        let mine = existing.filter { $0.operatorID == operatorID }
        let names = Set(mine.map(\.name))
        var order = (mine.map(\.sortOrder).max() ?? -1) + 1
        var added: [ServiceItem] = []
        for standard in ServiceItem.defaultServices where standard.category == category.key && !names.contains(standard.name) {
            let item = ServiceItem(name: standard.name, category: standard.category, unitType: standard.unitType,
                                   pricePerUnit: standard.price, isBuiltIn: true, operatorID: operatorID,
                                   sortOrder: order)
            context.insert(item)
            added.append(item)
            order += 1
        }
        return added
    }
}
