import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Import Clients, saved: tagged, customers marked so, properties to the
/// right client, and Undo This Import taking back only what nothing has used.
@MainActor
struct ClientImportSavingTests {
    let container: ModelContainer
    let context: ModelContext
    let now = Date(timeIntervalSinceReferenceDate: 813_000_000)
    let fields: [ClientImport.Field] = [.name, .phone, .address, .tags, .email, .notes]

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        context = container.mainContext
    }

    /// Rows of name, phone, address, then optionally tags, email, notes.
    private func preview(_ rows: [[String]], existing: [ClientImport.Known] = [],
                         properties: Bool = false) -> ClientImport.Preview {
        let table = CSVReader.Table(header: ["Name", "Phone", "Address", "Tags", "Email", "Notes"],
                                    rows: rows.map { $0 + Array(repeating: "", count: max(0, 6 - $0.count)) })
        return ClientImport.preview(table, fields: fields, existing: existing, addressesAsProperties: properties)
    }

    private func clients() throws -> [Client] {
        try context.fetch(FetchDescriptor<Client>(sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    private func save(_ preview: ClientImport.Preview, as kind: ClientImport.Kind = .customers,
                      at date: Date? = nil) throws -> ClientImport.Result {
        try ClientImport.save(preview, as: kind, operatorID: "op", in: context, now: date ?? now,
                              locale: Locale(identifier: "en_US"), timeZone: .gmt)
    }

    private func undo(_ result: ClientImport.Result) throws -> ClientImport.UndoPlan {
        try ClientImport.undo(result, in: context)
    }

    private func known(_ client: Client) -> [ClientImport.Known] {
        [ClientImport.Known(id: client.id.uuidString, name: client.name, phone: client.phone, address: client.address)]
    }

    @Test func newClientsAreSavedTaggedAndOnlyThem() throws {
        let existing = Client(name: "Pat Doe", phone: "603-555-0100", address: "1 Main St", operatorID: "op")
        context.insert(existing)
        let rows = [["Pat Doe", "603-555-0100", "1 Main St"],    // a duplicate
                    ["Sam Roe", "603-555-0200", "2 Elm St", "Weekly; weekly", "sam@example.com", "Gate 1234"],
                    ["", "603-555-0300", "3 Oak St"]]           // no name
        let result = try save(preview(rows, existing: known(existing)))
        #expect(result.clients == 1 && result.properties == 0)
        let sam = try #require(try clients().first { $0.name == "Sam Roe" })
        #expect(sam.tags == ["Weekly", result.tag])          // its own tags once, then the import's
        #expect(sam.operatorID == "op" && sam.address == "2 Elm St" && sam.createdAt == now)
        #expect(sam.email == "sam@example.com" && sam.notes == "Gate 1234")
        #expect(try clients().count == 2)
        #expect(existing.tags.isEmpty)                       // an existing client isn't touched
    }

    // A whole client list imported as customers mustn't fill the Pipeline
    // with leads; imported as leads, it should.
    @Test func customersAreCustomersAndLeadsAreLeads() throws {
        try save(preview([["Sam Roe", "", "2 Elm St"]]), as: .customers)
        try save(preview([["Lee Poe", "", "4 Pine St"]]), as: .leads)
        let facts = Pipeline.Facts(in: context)
        let byName = Dictionary(uniqueKeysWithValues: try clients().map { ($0.name, $0) })
        let sam = try #require(byName["Sam Roe"]), lee = try #require(byName["Lee Poe"])
        #expect(sam.customerSince == now && lee.customerSince == nil)
        #expect(Pipeline.stage(of: sam, facts: facts, now: now) == .customer)
        #expect(Pipeline.stage(of: lee, facts: facts, now: now) == .lead)
    }

    @Test func propertiesGoToTheRightClient() throws {
        let existing = Client(name: "Kim Poe", phone: "603-555-0900", address: "8 Hill St", operatorID: "op")
        context.insert(existing)
        let rows = [["Pat Doe", "603-555-0100", "1 Main St, Claremont"],
                    ["Pat Doe", "603-555-0100", "9 Lake Rd, Claremont"],
                    ["Kim Poe", "603-555-0900", "5 Barn Ln"]]
        let result = try save(preview(rows, existing: known(existing), properties: true))
        #expect(result.clients == 1 && result.properties == 2)
        let pat = try #require(try clients().first { $0.name == "Pat Doe" })
        #expect(pat.properties?.map(\.address) == ["9 Lake Rd, Claremont"])
        #expect(pat.properties?.first?.label == "9 Lake Rd")
        #expect(existing.properties?.map(\.address) == ["5 Barn Ln"])
    }

    @Test func twoPropertiesOfOneClientGoInOrder() throws {
        let kim = Client(name: "Kim Poe", phone: "603-555-0900", address: "8 Hill St", operatorID: "op")
        context.insert(kim)
        let barn = Property(label: "Barn", address: "1 Barn Ln", operatorID: "op")
        context.insert(barn)
        barn.client = kim
        barn.sortOrder = 4
        try save(preview([["Kim Poe", "603-555-0900", "5 Lake Rd"], ["Kim Poe", "603-555-0900", "6 Pond Rd"]],
                         existing: ClientImport.known(in: context, operatorID: "op"), properties: true))
        let orders = (kim.properties ?? []).sorted { $0.sortOrder < $1.sortOrder }.map { "\($0.address) \($0.sortOrder)" }
        #expect(orders == ["1 Barn Ln 4", "5 Lake Rd 5", "6 Pond Rd 6"])
    }

    @Test func aPropertyOfAClientGoneSinceThePreviewIsntSaved() throws {
        let gone = Client(name: "Kim Poe", phone: "603-555-0900", address: "8 Hill St", operatorID: "op")
        let result = try save(preview([["Kim Poe", "603-555-0900", "5 Barn Ln"]], existing: known(gone), properties: true))
        #expect(result.properties == 0 && result.propertiesSkipped == 1)
        #expect(try context.fetchCount(FetchDescriptor<Property>()) == 0)
    }

    @Test func aLongListIsSavedInBatches() throws {
        let rows = (0..<(ClientImport.batchSize * 2 + 3)).map { ["Client \($0)", "", "\($0) Main St"] }
        var saves = 0
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context,
                                                              queue: nil) { _ in saves += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        let result = try save(preview(rows))
        #expect(saves == 3)                   // 250, 500, and the last 3
        #expect(result.clients == rows.count)
        #expect(try context.fetchCount(FetchDescriptor<Client>()) == rows.count)
    }

    // Undo takes back what the import added and nothing has used; a client
    // put on a route since is kept, and so is everyone else.
    @Test func undoTakesBackOnlyWhatNothingHasUsed() throws {
        let existing = Client(name: "Kim Poe", phone: "603-555-0900", address: "8 Hill St", operatorID: "op")
        context.insert(existing)
        let rows = [["Sam Roe", "603-555-0200", "2 Elm St"],
                    ["Lee Poe", "603-555-0300", "4 Pine St"],
                    ["Lee Poe", "603-555-0300", "6 Pine St"],
                    ["Kim Poe", "603-555-0900", "5 Barn Ln"]]
        let result = try save(preview(rows, existing: known(existing), properties: true))
        // Another import five seconds later: the same tag, not the same import.
        let later = try save(preview([["Ann Coe", "", "7 Ash St"]]), at: now.addingTimeInterval(5))
        #expect(later.tag == result.tag)
        let sam = try #require(try clients().first { $0.name == "Sam Roe" })
        let route = PlowRoute(name: "Monday", operatorID: "op")
        context.insert(route)
        let stop = RouteStop(order: 0, client: sam)
        context.insert(stop)
        stop.route = route
        try context.save()

        let plan = try undo(result)
        #expect(plan.removable.map(\.name) == ["Lee Poe"] && plan.kept == 1)
        #expect(plan.properties.count == 1 && plan.keptProperties == 0)
        #expect(try clients().map(\.name) == ["Ann Coe", "Kim Poe", "Sam Roe"])
        #expect(existing.properties?.isEmpty ?? true)
        #expect(try context.fetchCount(FetchDescriptor<Property>()) == 0)     // Lee's went with Lee
        #expect(!context.hasChanges)
    }

    // Anything done with an imported client since keeps them: each kind of
    // record that would go with them.
    @Test(arguments: ["zone", "property", "text", "check", "visit", "contract", "document", "photo", "record",
                      "visits"])
    func undoKeepsAClientWorkedWith(_ kind: String) throws {
        let result = try save(preview([["Sam Roe", "", "2 Elm St"]]))
        let sam = try #require(try clients().first)
        let id = sam.id.uuidString
        switch kind {
        case "zone":
            let zone = PropertyZone(label: "Front")
            context.insert(zone)
            zone.client = sam
        case "property":
            let lake = Property(label: "Lake", address: "9 Lake Rd", operatorID: "op")
            context.insert(lake)
            lake.client = sam
        case "text":
            context.insert(SentText(clientID: id, kind: "onMyWay", body: "On my way", sentAt: now))
        case "check":
            context.insert(TriggerCheck(operatorID: "op", clientID: id, clientName: "Sam Roe", placeID: id, day: now))
        case "visit":
            context.insert(ScheduledVisit(operatorID: "op", clientID: id, clientName: "Sam Roe", clientAddress: "2 Elm St",
                                          scheduledDate: now.addingTimeInterval(-86_400)))
        case "document":
            context.insert(Proposal(operatorID: "op", client: sam))
        case "photo":
            context.insert(StopPhoto(operatorID: "op", clientID: id, routeID: "", isBefore: true, imageData: Data([1])))
        case "record":
            let record = ServiceRecord(operatorID: "op", sourceKey: "manual:1", source: .manual)
            record.clientID = id
            context.insert(record)
        case "visits":
            sam.totalVisits = 1
        default:
            let contract = Contract(name: "Season", startDate: now, endDate: now.addingTimeInterval(86_400 * 90),
                                    operatorID: "op")
            context.insert(contract)
            contract.client = sam
        }
        try context.save()
        let plan = try undo(result)
        #expect(plan.removable.isEmpty && plan.kept == 1, "\(kind)")
        #expect(try clients().count == 1)
    }

    // A property the import added to a client PlowR had, worked at since
    // (a visit done there), stays.
    @Test func undoKeepsAPropertyWorkedAt() throws {
        let kim = Client(name: "Kim Poe", phone: "603-555-0900", address: "8 Hill St", operatorID: "op")
        context.insert(kim)
        let result = try save(preview([["Kim Poe", "603-555-0900", "5 Barn Ln"]],
                                      existing: known(kim), properties: true))
        let barn = try #require(kim.properties?.first)
        let visit = ScheduledVisit(operatorID: "op", clientID: kim.id.uuidString, clientName: "Kim Poe",
                                   clientAddress: "5 Barn Ln", scheduledDate: now.addingTimeInterval(-86_400))
        visit.propertyID = barn.id.uuidString
        visit.status = .completed
        context.insert(visit)
        try context.save()
        let plan = try undo(result)
        #expect(plan.properties.isEmpty && plan.keptProperties == 1)
        #expect(kim.properties?.count == 1)
    }

    // iCloud keeps dates to the millisecond: an import still finds its own.
    @Test func anImportIsFoundAtWholeSeconds() throws {
        let result = try save(preview([["Sam Roe", "", "2 Elm St"]]), at: now.addingTimeInterval(0.4567))
        #expect(result.date == now)
        let sam = try #require(try clients().first)
        sam.createdAt = now.addingTimeInterval(0.0004)
        #expect(ClientImport.clients(of: result, in: context).count == 1)
        sam.tags = []                                         // the user took the tag off: theirs now
        #expect(ClientImport.clients(of: result, in: context).isEmpty)
    }

    @Test func theTagSaysWhen() {
        let date = Date(timeIntervalSince1970: 1_791_382_500)          // Oct 7 2026, 14:15 GMT
        let tag = ClientImport.tag(for: date, locale: Locale(identifier: "en_US"), timeZone: .gmt)
        #expect(tag.replacingOccurrences(of: "\u{202F}", with: " ") == "Imported Oct 7 at 2:15 PM", "\(tag)")
    }

    @Test func knownClientsAreThisBusinesssAtEveryPlace() throws {
        let pat = Client(name: "Pat Doe", phone: "603-555-0100", address: "1 Main St", operatorID: "op")
        pat.isActive = false
        let other = Client(name: "Sam Roe", phone: "603-555-0200", address: "2 Elm St", operatorID: "someone else")
        let lake = Property(label: "Lake", address: "9 Lake Rd", operatorID: "op")
        for model in [pat, other, lake] as [any PersistentModel] { context.insert(model) }
        lake.client = pat
        try context.save()
        let known = ClientImport.known(in: context, operatorID: "op")
        #expect(known.map(\.address).sorted() == ["1 Main St", "9 Lake Rd"])
        #expect(Set(known.map(\.id)) == [pat.id.uuidString])
    }

    // An undo shown earlier, then a client put on a route by iCloud: the
    // undo works it out afresh and keeps them.
    @Test func undoChecksAgainWhenItRuns() throws {
        let result = try save(preview([["Sam Roe", "", "2 Elm St"]]))
        #expect(ClientImport.undoPlan(for: result, in: context).removable.count == 1)
        let sam = try #require(try clients().first)
        let route = PlowRoute(name: "Monday", operatorID: "op")
        context.insert(route)
        let stop = RouteStop(order: 0, client: sam)
        context.insert(stop)
        stop.route = route
        try context.save()
        #expect(try undo(result).kept == 1)
        #expect(route.stops?.count == 1)
    }

    // A client the user kept (took the import's tag off) keeps the
    // property the import gave them.
    @Test func aKeptClientKeepsTheirImportedProperty() throws {
        let result = try save(preview([["Pat Doe", "603-555-0100", "1 Main St"], ["Pat Doe", "603-555-0100", "9 Lake Rd"]],
                                      properties: true))
        let pat = try #require(try clients().first)
        pat.tags = []
        try context.save()
        let plan = try undo(result)
        #expect(plan.removable.isEmpty && plan.properties.isEmpty)
        #expect(pat.properties?.count == 1)
    }

    // A save that fails partway takes back what was saved, so nothing is
    // half imported and a retry adds no one twice.
    @Test func aFailedSaveTakesTheImportBack() throws {
        let rows = (0..<(ClientImport.batchSize + 5)).map { ["Client \($0)", "", "\($0) Main St"] }
        var saves = 0
        struct DiskFull: Error {}
        #expect(throws: DiskFull.self) {
            try ClientImport.save(preview(rows), as: .customers, operatorID: "op", in: context, now: now) { context in
                saves += 1
                if saves == 2 { throw DiskFull() }
                try context.save()
            }
        }
        #expect(try context.fetchCount(FetchDescriptor<Client>()) == 0)
        #expect(!context.hasChanges)
    }

    // Undo is offered later too: each import still tagged, newest first,
    // two in one minute apart, and only this business's.
    @Test func recentImportsAreFoundFromTheStore() throws {
        let first = try save(preview([["Sam Roe", "", "2 Elm St"], ["Lee Poe", "", "4 Pine St"]]))
        let second = try save(preview([["Ann Coe", "", "7 Ash St"]]), at: now.addingTimeInterval(5))
        let theirs = Client(name: "Kim Poe", phone: "", address: "", operatorID: "someone else")
        theirs.tags = [first.tag]
        context.insert(theirs)
        try context.save()
        let recent = ClientImport.recentImports(in: context, operatorID: "op")
        #expect(recent.map(\.date) == [second.date, first.date])
        #expect(recent.map(\.clients) == [1, 2])
        #expect(try ClientImport.undo(try #require(recent.last), in: context).removable.count == 2)
        #expect(ClientImport.recentImports(in: context, operatorID: "op").map(\.date) == [second.date])
    }

    // A PlowR export re-imported carries the old import's tag: only the new
    // one is kept, so Recent Imports lists the import once, under its date.
    @Test func anOldImportTagInTheFileIsDropped() throws {
        let result = try save(preview([["Sam Roe", "", "2 Elm St", "Imported Oct 1 at 3:00 PM; VIP"]]))
        let sam = try #require(try clients().first)
        #expect(sam.tags == ["VIP", result.tag])
        #expect(ClientImport.recentImports(in: context, operatorID: "op") == [result])
    }

    // A client added by hand with a tag of the user's own beginning
    // "Imported " isn't taken for an import (it would offer to undo it).
    @Test func aHandMadeClientIsntAnImport() throws {
        let kim = Client(name: "Kim Poe", phone: "", address: "", operatorID: "op")
        kim.tags = ["Imported from my old app"]
        kim.createdAt = now.addingTimeInterval(0.25)
        context.insert(kim)
        try context.save()
        #expect(ClientImport.recentImports(in: context, operatorID: "op").isEmpty)
    }

    // What Import Clients brings back from PlowR's own Clients export, as
    // Export Data says: names, phones, emails, addresses, tags and notes.
    @Test func plowrsOwnExportComesBack() throws {
        let pat = Client(name: "Pat Doe", phone: "603-555-0100", address: "1 Main St, Claremont, NH 03743",
                         operatorID: "op")
        pat.email = "pat@example.com"
        pat.tags = ["Weekly", "VIP"]
        pat.notes = "Gate 1234"
        pat.isActive = false
        context.insert(pat)
        try context.save()
        let table = try CSVReader.read(Data(CSVExport.clients([pat], operatorID: "op").utf8))
        let fields = ClientImport.guess(table.header, rows: table.rows)
        let draft = ClientImport.draft(from: try #require(table.rows.first), fields: fields)
        #expect(draft == ClientImport.Draft(name: "Pat Doe", phone: "603-555-0100", email: "pat@example.com",
                                            address: "1 Main St, Claremont, NH 03743", notes: "Gate 1234",
                                            tags: ["Weekly", "VIP"]))
        // Into another business's PlowR, as a new client; into this one, a duplicate.
        #expect(ClientImport.preview(table, fields: fields, existing: []).new.count == 1)
        #expect(ClientImport.preview(table, fields: fields,
                                     existing: ClientImport.known(in: context, operatorID: "op")).duplicates == 1)
    }

    // Only PlowR's own import tags are dropped from a file; the user's are kept.
    @Test func aUsersOwnImportedTagIsKept() throws {
        let result = try save(preview([["Sam Roe", "", "2 Elm St", "Imported from Jobber; Imported Oct 1 at 3:00 PM; VIP"]]))
        let sam = try #require(try clients().first)
        #expect(sam.tags == ["Imported from Jobber", "VIP", result.tag])
        #expect(ClientImport.recentImports(in: context, operatorID: "op").map(\.tag) == [result.tag])
        #expect(ClientImport.isImportTag(result.tag) && !ClientImport.isImportTag("Imported from Jobber"))
    }
}
