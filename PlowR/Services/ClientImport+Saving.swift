import Foundation
import SwiftData

/// Import Clients, saved: the preview's new clients added, each tagged with
/// the import ("Imported Oct 7 at 2:15 PM") so the import can be found and
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
        /// When, to the second: every client and property it added was made
        /// at this moment, which tells two imports in one minute apart.
        var date: Date
        var clients: Int
        var properties: Int
        /// Properties of clients deleted since the preview, not saved.
        var propertiesSkipped = 0
    }

    /// How every import's tag begins.
    static let tagPrefix = "Imported "

    /// Saved every this many new clients, so a long list isn't one huge save.
    static let batchSize = 250

    /// The tag that marks an import made at `date`.
    static func tag(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute().locale(locale)
        style.timeZone = timeZone
        return tagPrefix + date.formatted(style)
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

    /// Saves `preview`'s new clients and properties for `operatorID`. All
    /// or nothing: if a save fails, what was saved of it is taken back
    /// before the error is thrown, so a retry doesn't add anyone twice.
    @discardableResult
    static func save(_ preview: Preview, as kind: Kind, operatorID: String, in context: ModelContext,
                     now: Date = .now, locale: Locale = .current, timeZone: TimeZone = .current) throws -> Result {
        // Whole seconds: iCloud keeps dates to the millisecond, so a finer
        // one wouldn't match itself once synced.
        let date = Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down))
        let tag = tag(for: date, locale: locale, timeZone: timeZone)
        var result = Result(tag: tag, date: date, clients: 0, properties: 0)
        var added: [String: Client] = [:]       // by "row:N", as the preview names them
        do {
            for (index, outcome) in preview.outcomes.enumerated() {
                switch outcome {
                case let .new(draft, _):
                    let client = Client(name: draft.name, phone: draft.phone, address: draft.address,
                                        operatorID: operatorID)
                    client.email = draft.email
                    client.notes = draft.notes
                    client.tags = unique(draft.tags.filter { !isTag($0, tag) } + [tag])
                    client.createdAt = date
                    client.customerSince = kind == .customers ? date : nil
                    context.insert(client)
                    added["row:\(index)"] = client
                    result.clients += 1
                    if result.clients % batchSize == 0 { try context.save() }
                case let .property(draft, _, ofID):
                    guard let owner = added[ofID] ?? existingClient(ofID, in: context) else {
                        result.propertiesSkipped += 1
                        continue
                    }
                    let property = Property(label: label(for: draft.address), address: draft.address,
                                            operatorID: owner.operatorID)
                    property.createdAt = date
                    property.sortOrder = Property.nextSortOrder(for: owner)
                    context.insert(property)
                    property.client = owner
                    result.properties += 1
                case .duplicate, .problem:
                    continue
                }
            }
            try context.save()
        } catch {
            takeBack(result, in: context)
            throw error
        }
        return result
    }

    /// After a failed save: what wasn't saved dropped, and what was deleted.
    private static func takeBack(_ result: Result, in context: ModelContext) {
        context.rollback()
        for client in clients(of: result, in: context) { context.delete(client) }
        for property in properties(of: result, in: context) { context.delete(property) }
        try? context.save()
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

    private static func isTag(_ tag: String, _ other: String) -> Bool {
        tag.caseInsensitiveCompare(other) == .orderedSame
    }

    /// Within a second of `date`: as saved, or as iCloud brings it back.
    private static func isAt(_ created: Date, _ date: Date) -> Bool {
        abs(created.timeIntervalSince(date)) < 1
    }

    /// The clients `result` added that are still here with its tag (one
    /// whose tag the user took off is theirs now).
    static func clients(of result: Result, in context: ModelContext) -> [Client] {
        let from = result.date.addingTimeInterval(-1), to = result.date.addingTimeInterval(1)
        let made = (try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate {
            $0.createdAt > from && $0.createdAt < to
        }))) ?? []
        return made.filter { client in client.tags.contains { isTag($0, result.tag) } }
    }

    /// The properties `result` added: made at its moment.
    static func properties(of result: Result, in context: ModelContext) -> [Property] {
        let from = result.date.addingTimeInterval(-1), to = result.date.addingTimeInterval(1)
        return (try? context.fetch(FetchDescriptor<Property>(predicate: #Predicate {
            $0.createdAt > from && $0.createdAt < to
        }))) ?? []
    }

    // MARK: - Undo

    /// What Undo This Import would do. The clients it added that have
    /// nothing in PlowR but what the import gave them are deleted; any
    /// worked with since are kept, and counted, so undoing never loses work.
    /// The same for properties it added to clients already in PlowR.
    struct UndoPlan {
        var removable: [Client]
        var kept: Int
        var properties: [Property]
        var keptProperties: Int
    }

    static func undoPlan(for result: Result, in context: ModelContext) -> UndoPlan {
        let tagged = clients(of: result, in: context)
        let removable = tagged.filter { isUntouched($0, since: result.date, in: context) }
        let others = properties(of: result, in: context).filter { property in
            guard let owner = property.client else { return false }
            return !tagged.contains(owner)
        }
        let removableProperties = others.filter { isUntouched($0, in: context) }
        return UndoPlan(removable: removable, kept: tagged.count - removable.count, properties: removableProperties,
                        keptProperties: others.count - removableProperties.count)
    }

    /// Carries out `plan`, in one save.
    static func undo(_ plan: UndoPlan, in context: ModelContext) throws {
        for property in plan.properties { PropertyRemoval.remove(property, in: context, saving: false) }
        for client in plan.removable { ClientRemoval.delete(client, keepingRecords: false, in: context, saving: false) }
        try context.save()
    }

    /// Nothing in PlowR but what the import made: no route stop, visit,
    /// invoice or proposal, contract, photo, Service Log record, day below
    /// the trigger, text, measured area, or property added later.
    static func isUntouched(_ client: Client, since date: Date, in context: ModelContext) -> Bool {
        let id = client.id.uuidString
        let footprint = ClientRemoval.footprint(of: client, in: context)
        return client.totalVisits == 0 && footprint.routeNames.isEmpty && footprint.visitsAhead == 0
            && footprint.pastVisits == 0 && footprint.documents == 0 && footprint.photos == 0
            && (client.contracts ?? []).isEmpty && (client.zones ?? []).isEmpty
            && (client.properties ?? []).allSatisfy { isAt($0.createdAt, date) && isUntouched($0, in: context) }
            && ServiceLog.records(ofClient: id, in: context).isEmpty
            && TriggerChecks.of(clientID: id, in: context).isEmpty
            && TextLog.texts(ofClient: id, in: context).isEmpty
    }

    /// Nothing at the property: no route stop, visit (of any day), Service
    /// Log record, day below the trigger, or contract covering it.
    static func isUntouched(_ property: Property, in context: ModelContext) -> Bool {
        let id = property.id.uuidString
        let visits = (try? context.fetchCount(FetchDescriptor<ScheduledVisit>(predicate: #Predicate { $0.propertyID == id }))) ?? 0
        let records = (try? context.fetchCount(FetchDescriptor<ServiceRecord>(predicate: #Predicate { $0.propertyID == id }))) ?? 0
        let checks = (try? context.fetchCount(FetchDescriptor<TriggerCheck>(predicate: #Predicate { $0.placeID == id }))) ?? 0
        let contracts = (property.client?.contracts ?? []).contains { $0.placeIDs.contains(id) }
        return PropertyRemoval.stops(of: property, in: context).isEmpty && visits == 0 && records == 0 && checks == 0
            && !contracts
    }
}
