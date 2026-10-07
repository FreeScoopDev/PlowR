import Foundation
import SwiftData

/// Import Clients, saved: the preview's new clients added, each tagged with
/// the import ("Imported Oct 7, 2:15 PM") so the import can be found and
/// undone; current customers marked so (`customerSince`) so the Pipeline
/// doesn't list a whole client list as leads; and the addresses asked for
/// kept as properties. Duplicates and rows with problems aren't saved.
@MainActor
extension ClientImport {
    /// What the file is: the business's clients now, or people to win.
    enum Kind {
        case customers, leads
    }

    /// What an import saved.
    struct Result: Equatable {
        /// The tag on every client it added.
        var tag: String
        /// When: every client and property it added was made at this moment.
        var date: Date
        var clients: Int
        var properties: Int
    }

    /// What the preview matches rows against: `operatorID`'s clients, one
    /// per place (their own address and each property's), inactive ones too,
    /// so an import doesn't bring back a client the business let go.
    static func known(in context: ModelContext, operatorID: String) -> [Known] {
        let clients = (try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.operatorID == operatorID }))) ?? []
        return clients.flatMap { client in
            let id = client.id.uuidString
            return [Known(id: id, name: client.name, phone: client.phone, address: client.address)]
                + (client.properties ?? []).map { Known(id: id, name: client.name, phone: client.phone, address: $0.address) }
        }
    }

    /// Saved every this many new clients, so a long list isn't one huge save.
    static let batchSize = 250

    /// The tag that marks an import made at `date`.
    static func tag(for date: Date, locale: Locale = .current) -> String {
        "Imported " + date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))
    }

    /// Saves `preview`'s new clients and properties for `operatorID`.
    /// A property of a client that's gone since the preview (deleted on
    /// another device) isn't saved.
    @discardableResult
    static func save(_ preview: Preview, as kind: Kind, operatorID: String, in context: ModelContext,
                     now: Date = .now, locale: Locale = .current) throws -> Result {
        let tag = tag(for: now, locale: locale)
        var added: [String: Client] = [:]       // by "row:N", as the preview names them
        var clients = 0, properties = 0
        for (index, outcome) in preview.outcomes.enumerated() {
            switch outcome {
            case let .new(draft, _):
                let client = Client(name: draft.name, phone: draft.phone, address: draft.address, operatorID: operatorID)
                client.email = draft.email
                client.notes = draft.notes
                client.tags = unique(draft.tags + [tag])
                client.createdAt = now
                client.customerSince = kind == .customers ? now : nil
                context.insert(client)
                added["row:\(index)"] = client
                clients += 1
                if clients % batchSize == 0 { try context.save() }
            case let .property(draft, _, ofID):
                guard let owner = added[ofID] ?? existingClient(ofID, in: context) else { continue }
                let property = Property(label: label(for: draft.address), address: draft.address,
                                        operatorID: owner.operatorID)
                property.createdAt = now
                property.sortOrder = (owner.properties ?? []).map(\.sortOrder).max().map { $0 + 1 } ?? 0
                context.insert(property)
                property.client = owner
                properties += 1
            case .duplicate, .problem:
                continue
            }
        }
        try context.save()
        return Result(tag: tag, date: now, clients: clients, properties: properties)
    }

    /// A property's name until the business gives it one: the street, the
    /// part of the address before its first comma.
    static func label(for address: String) -> String {
        String(address.split(separator: ",").first ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func existingClient(_ id: String, in context: ModelContext) -> Client? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.id == uuid })).first
    }

    private static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Undo

    /// What Undo This Import would do: the clients it added that still have
    /// nothing else in PlowR are deleted; any given work since (a route stop,
    /// a visit, an invoice or proposal, a contract, a photo, a Service Log
    /// record) are kept, and counted, so nothing done with them is lost.
    struct UndoPlan {
        var removable: [Client]
        var kept: Int
        /// Properties the import added to clients it didn't (the import's
        /// own clients' properties go with them).
        var properties: [Property]
    }

    static func undoPlan(for result: Result, in context: ModelContext) -> UndoPlan {
        let tag = result.tag
        let tagged = ((try? context.fetch(FetchDescriptor<Client>())) ?? [])
            .filter { $0.tags.contains(tag) && $0.createdAt == result.date }
        let removable = tagged.filter { isUntouched($0, in: context) }
        let date = result.date
        let added = ((try? context.fetch(FetchDescriptor<Property>(predicate: #Predicate { $0.createdAt == date }))) ?? [])
            .filter { property in
                guard let owner = property.client, !tagged.contains(owner) else { return false }
                let used = PropertyRemoval.footprint(of: property, in: context)
                return used.stops == 0 && used.visits == 0
            }
        return UndoPlan(removable: removable, kept: tagged.count - removable.count, properties: added)
    }

    /// Undoes the import as `undoPlan` says; returns what was kept.
    @discardableResult
    static func undo(_ result: Result, in context: ModelContext) -> UndoPlan {
        let plan = undoPlan(for: result, in: context)
        for property in plan.properties { PropertyRemoval.remove(property, in: context) }
        for client in plan.removable { ClientRemoval.delete(client, keepingRecords: false, in: context) }
        try? context.save()
        return plan
    }

    /// Nothing in PlowR but the client: safe for an undo to delete.
    static func isUntouched(_ client: Client, in context: ModelContext) -> Bool {
        let footprint = ClientRemoval.footprint(of: client, in: context)
        return client.totalVisits == 0 && footprint.routeNames.isEmpty && footprint.visitsAhead == 0
            && footprint.pastVisits == 0 && footprint.documents == 0 && footprint.photos == 0
            && (client.contracts ?? []).isEmpty
            && ServiceLog.records(ofClient: client.id.uuidString, in: context).isEmpty
    }
}
