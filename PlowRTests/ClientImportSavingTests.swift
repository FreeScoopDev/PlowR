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
    let fields: [ClientImport.Field] = [.name, .phone, .address, .tags]

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        context = container.mainContext
    }

    private func preview(_ rows: [[String]], existing: [ClientImport.Known] = [],
                         properties: Bool = false) -> ClientImport.Preview {
        ClientImport.preview(CSVReader.Table(header: ["Name", "Phone", "Address", "Tags"], rows: rows),
                             fields: fields, existing: existing, addressesAsProperties: properties)
    }

    private func clients() throws -> [Client] {
        try context.fetch(FetchDescriptor<Client>(sortBy: [SortDescriptor(\.name)]))
    }

    private func save(_ preview: ClientImport.Preview, as kind: ClientImport.Kind = .customers) throws
        -> ClientImport.Result {
        try ClientImport.save(preview, as: kind, operatorID: "op", in: context, now: now,
                              locale: Locale(identifier: "en_US"))
    }

    @Test func newClientsAreSavedTaggedAndOnlyThem() throws {
        let existing = Client(name: "Pat Doe", phone: "603-555-0100", address: "1 Main St", operatorID: "op")
        context.insert(existing)
        let rows = [["Pat Doe", "603-555-0100", "1 Main St", ""],    // a duplicate
                    ["Sam Roe", "603-555-0200", "2 Elm St", "Weekly; weekly"],
                    ["", "603-555-0300", "3 Oak St", ""]]          // no name
        let known = [ClientImport.Known(id: existing.id.uuidString, name: existing.name, phone: existing.phone,
                                        address: existing.address)]
        let result = try save(preview(rows, existing: known))
        #expect(result.clients == 1 && result.properties == 0)
        #expect(result.tag.hasPrefix("Imported "))
        let sam = try #require(try clients().first { $0.name == "Sam Roe" })
        #expect(sam.tags == ["Weekly", result.tag])          // its own tags once, then the import's
        #expect(sam.operatorID == "op" && sam.address == "2 Elm St" && sam.createdAt == now)
        #expect(try clients().count == 2)
        #expect(existing.tags.isEmpty)                       // an existing client isn't touched
    }

    // A whole client list imported as customers mustn't fill the Pipeline
    // with leads; imported as leads, it should.
    @Test func customersAreCustomersAndLeadsAreLeads() throws {
        try save(preview([["Sam Roe", "", "2 Elm St", ""]]), as: .customers)
        try save(preview([["Lee Poe", "", "4 Pine St", ""]]), as: .leads)
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
        let known = [ClientImport.Known(id: existing.id.uuidString, name: existing.name, phone: existing.phone,
                                        address: existing.address)]
        let rows = [["Pat Doe", "603-555-0100", "1 Main St, Claremont", ""],
                    ["Pat Doe", "603-555-0100", "9 Lake Rd, Claremont", ""],
                    ["Kim Poe", "603-555-0900", "5 Barn Ln", ""]]
        let result = try save(preview(rows, existing: known, properties: true))
        #expect(result.clients == 1 && result.properties == 2)
        let pat = try #require(try clients().first { $0.name == "Pat Doe" })
        #expect(pat.properties?.map(\.address) == ["9 Lake Rd, Claremont"])
        #expect(pat.properties?.first?.label == "9 Lake Rd")
        #expect(existing.properties?.map(\.address) == ["5 Barn Ln"])
    }

    @Test func aPropertyOfAClientGoneSinceThePreviewIsntSaved() throws {
        let gone = Client(name: "Kim Poe", phone: "603-555-0900", address: "8 Hill St", operatorID: "op")
        let known = [ClientImport.Known(id: gone.id.uuidString, name: gone.name, phone: gone.phone, address: gone.address)]
        let result = try save(preview([["Kim Poe", "603-555-0900", "5 Barn Ln", ""]], existing: known, properties: true))
        #expect(result.properties == 0)
        #expect(try context.fetchCount(FetchDescriptor<Property>()) == 0)
    }

    @Test func aLongListIsSavedInBatches() throws {
        let rows = (0..<(ClientImport.batchSize * 2 + 3)).map { ["Client \($0)", "", "\($0) Main St", ""] }
        let result = try save(preview(rows))
        #expect(result.clients == rows.count)
        #expect(try context.fetchCount(FetchDescriptor<Client>()) == rows.count)
    }

    // Undo takes back what the import added and nothing has used; a client
    // put on a route since is kept, and so is everyone else.
    @Test func undoTakesBackOnlyWhatNothingHasUsed() throws {
        let existing = Client(name: "Kim Poe", phone: "603-555-0900", address: "8 Hill St", operatorID: "op")
        context.insert(existing)
        let known = [ClientImport.Known(id: existing.id.uuidString, name: existing.name, phone: existing.phone,
                                        address: existing.address)]
        let rows = [["Sam Roe", "603-555-0200", "2 Elm St", ""],
                    ["Lee Poe", "603-555-0300", "4 Pine St", ""],
                    ["Lee Poe", "603-555-0300", "6 Pine St", ""],
                    ["Kim Poe", "603-555-0900", "5 Barn Ln", ""]]
        let result = try save(preview(rows, existing: known, properties: true))
        // An import a minute later, which this undo mustn't touch.
        let later = try ClientImport.save(preview([["Ann Coe", "", "7 Ash St", ""]]), as: .customers,
                                          operatorID: "op", in: context, now: now.addingTimeInterval(60))
        let sam = try #require(try clients().first { $0.name == "Sam Roe" })
        let route = PlowRoute(name: "Monday", operatorID: "op")
        context.insert(route)
        let stop = RouteStop(order: 0, client: sam)
        context.insert(stop)
        stop.route = route
        try context.save()

        let plan = ClientImport.undoPlan(for: result, in: context)
        #expect(plan.removable.map(\.name) == ["Lee Poe"] && plan.kept == 1 && plan.properties.count == 1)
        ClientImport.undo(result, in: context)
        #expect(try clients().map(\.name) == ["Ann Coe", "Kim Poe", "Sam Roe"])
        #expect(existing.properties?.isEmpty ?? true)
        #expect(try context.fetchCount(FetchDescriptor<Property>()) == 0)     // Lee's went with Lee
        #expect(later.clients == 1)
    }

    @Test func theTagSaysWhen() {
        let tag = ClientImport.tag(for: now, locale: Locale(identifier: "en_US"))
        #expect(tag.hasPrefix("Imported ") && tag.contains(":"))
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
}
