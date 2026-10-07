import Foundation
import SwiftData

/// Adding and changing a client's additional properties (PropertyEditView),
/// as plain values, so the rules are tested without the screen.
enum PropertyEditing {
    /// What the property's page has on screen.
    struct Draft: Equatable {
        var label = ""
        var address = ""
        var latitude = 0.0
        var longitude = 0.0
        var stopNotes = ""
        var goalMinutes = 0
        var expectedServiceIDs: Set<String> = []
        var isActive = true

        init() {}

        nonisolated init(_ property: Property) {
            label = property.label
            address = property.address
            latitude = property.latitude
            longitude = property.longitude
            stopNotes = property.stopNotes
            goalMinutes = property.goalMinutes
            expectedServiceIDs = Set(property.expectedServiceIDs)
            isActive = property.isActive
        }

        /// It needs an address: that's where the work is.
        var canSave: Bool { !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var hasPin: Bool { AddressPin.exists(latitude: latitude, longitude: longitude) }
    }

    /// `draft` saved to `property`, or as a new property of `client`, last
    /// in their order. Its stops and visits move with it at once
    /// (ClientStops.update), as they do when a client is edited; other
    /// devices catch up on their next sweep.
    @discardableResult
    static func save(_ draft: Draft, to property: Property?, of client: Client,
                     in context: ModelContext) -> Property {
        let target: Property
        if let property {
            target = property
        } else {
            target = Property(label: "", address: "", operatorID: client.operatorID)
            target.sortOrder = Property.nextSortOrder(for: client)
            context.insert(target)
            target.client = client
        }
        if target.isActive, !draft.isActive { PropertyRemoval.takeOffRoutes(target, in: context) }
        target.label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        // A new address loses the old one's not-found mark: it's looked up once.
        if address != target.address { target.addressNotFoundAt = nil }
        target.address = address
        target.latitude = draft.latitude
        target.longitude = draft.longitude
        target.stopNotes = draft.stopNotes
        target.goalMinutes = draft.goalMinutes
        target.expectedServiceIDs = draft.expectedServiceIDs.sorted()
        target.isActive = draft.isActive
        ClientStops.update(for: client)
        try? context.save()
        return target
    }

    /// Whether saving `draft` marks `property` inactive while it's on routes,
    /// which asks first: they're the routes it comes off.
    static func routesLeft(saving draft: Draft, to property: Property?, in context: ModelContext) -> [String] {
        guard let property, property.isActive, !draft.isActive else { return [] }
        return PropertyRemoval.routeNames(of: property, in: context)
    }

    static func deactivateMessage(routeNames: [String], locale: Locale = .current) -> String {
        "It'll be taken off \(ClientRemoval.routes(routeNames, locale)). Marking it active again won't put it back."
    }

    /// What removing `property` takes with it, as the confirmation says it.
    static func removalMessage(stops: Int, visits: Int) -> String {
        var parts: [String] = []
        if stops > 0 { parts.append(stops == 1 ? "1 route stop" : "\(stops) route stops") }
        if visits > 0 { parts.append(visits == 1 ? "1 visit not done yet" : "\(visits) visits not done yet") }
        let taken = parts.isEmpty ? "" : "This also removes \(parts.joined(separator: " and ")). "
        return taken + "Work already done there stays in the client's Service History."
    }
}
