import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Pins for imported clients, looked up in the background: only what an
/// import left without one, for the business signed in, slowing down when
/// the map refuses, and carrying on from the store after a relaunch.
@MainActor
struct ImportPinsTests {
    let container: ModelContainer
    let context: ModelContext
    let date = Date(timeIntervalSinceReferenceDate: 813_000_000)

    init() throws {
        container = try ModelContainer(for: Schema(PlowRApp.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                          cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        context = container.mainContext
    }

    /// Imports `rows` (name, phone, address) for `operatorID`, against the
    /// clients already here, extra addresses as properties.
    @discardableResult
    private func importRows(_ rows: [[String]], at when: Date? = nil, operatorID: String = "op") throws
        -> ClientImport.Result {
        let table = CSVReader.Table(header: ["Name", "Phone", "Address"], rows: rows)
        let preview = ClientImport.preview(table, fields: [.name, .phone, .address],
                                           existing: ClientImport.known(in: context, operatorID: operatorID),
                                           addressesAsProperties: true)
        return try ClientImport.save(preview, as: .customers, operatorID: operatorID, in: context, now: when ?? date)
    }

    /// A map that knows `known`, refuses `refusals` times first, and counts.
    final class FakeMap {
        var known: [String: (Double, Double)]
        var refusals: Int
        var asked: [String] = []
        var pauses: [Duration] = []
        init(_ known: [String: (Double, Double)], refusals: Int = 0) {
            self.known = known
            self.refusals = refusals
        }
        func lookUp(_ address: String) -> AddressPin.Lookup {
            asked.append(address)
            if refusals > 0 {
                refusals -= 1
                return .failed(.unreachable)
            }
            guard let spot = known[address] else { return .failed(.notFound) }
            return .found(latitude: spot.0, longitude: spot.1)
        }
    }

    private func pins(_ map: FakeMap) -> ImportPins {
        ImportPins(lookUp: { map.lookUp($0) }, pause: { map.pauses.append($0) })
    }

    private func client(_ name: String) throws -> Client {
        try #require(try context.fetch(FetchDescriptor<Client>()).first { $0.name == name })
    }

    @Test func importedClientsAndPropertiesGetPinsAndMissesAreListed() async throws {
        try importRows([["Pat Doe", "603-555-0100", "1 Main St"], ["Pat Doe", "603-555-0100", "9 Lake Rd"],
                        ["Sam Roe", "", "2 Nowhere Ln"], ["Lee Poe", "", ""]])
        let mine = Client(name: "Kim Coe", phone: "", address: "5 Ash St", operatorID: "op")   // not imported
        context.insert(mine)
        let map = FakeMap(["1 Main St": (43.1, -72.1), "9 Lake Rd": (43.2, -72.2), "5 Ash St": (1, 1)])
        let importPins = pins(map)
        await importPins.run(in: context, operatorID: "op")
        // Clients, then properties; Lee has no address and Kim isn't imported.
        #expect(Set(map.asked.prefix(2)) == ["1 Main St", "2 Nowhere Ln"] && map.asked.last == "9 Lake Rd")
        #expect(map.asked.count == 3)
        let pat = try client("Pat Doe")
        #expect(pat.latitude == 43.1 && pat.longitude == -72.1)
        #expect(pat.properties?.first?.latitude == 43.2)
        #expect(importPins.notFound.map(\.name) == ["Sam Roe"])
        #expect(importPins.done == 3 && importPins.total == 3 && !importPins.isRunning)
        #expect(!context.hasChanges)                                         // saved
        // Not looked up again this session; the count stays.
        await importPins.run(in: context, operatorID: "op")
        #expect(map.asked.count == 3 && importPins.done == 3 && importPins.total == 3)
    }

    // An import that only adds addresses to clients PlowR had: those get pins.
    @Test func propertiesAddedToExistingClientsGetPins() async throws {
        let pat = Client(name: "Pat Doe", phone: "603-555-0100", address: "1 Main St", operatorID: "op")
        pat.latitude = 1
        context.insert(pat)
        let byHand = Property(label: "Shed", address: "3 Shed Rd", operatorID: "op")   // made by hand: not imported
        byHand.createdAt = date.addingTimeInterval(0.25)
        context.insert(byHand)
        byHand.client = pat
        try context.save()
        let result = try importRows([["Pat Doe", "603-555-0100", "9 Lake Rd"]])
        #expect(result.clients == 0 && result.properties == 1)
        let map = FakeMap(["9 Lake Rd": (2, 2), "3 Shed Rd": (3, 3)])
        await pins(map).run(in: context, operatorID: "op")
        #expect(map.asked == ["9 Lake Rd"])
        #expect(pat.properties?.first { $0.address == "9 Lake Rd" }?.latitude == 2)
    }

    // Only the business signed in: another's clients on a shared device
    // aren't looked up or listed.
    @Test func onlyTheSignedInBusinesssClients() async throws {
        try importRows([["Pat Doe", "", "1 Main St"]], operatorID: "a")
        try importRows([["Sam Roe", "", "2 Elm St"]], at: date.addingTimeInterval(60), operatorID: "b")
        let map = FakeMap([:])
        let importPins = pins(map)
        await importPins.run(in: context, operatorID: "a")
        #expect(map.asked == ["1 Main St"] && importPins.notFound.map(\.name) == ["Pat Doe"])
        await importPins.run(in: context, operatorID: "")                    // signed out
        #expect(map.asked.count == 1)
    }

    @Test func aRefusingMapSlowsDownThenWaitsForTheWholeRun() async throws {
        try importRows([["Pat Doe", "", "1 Main St"]])
        let map = FakeMap(["1 Main St": (43.1, -72.1)], refusals: 2)
        let importPins = pins(map)
        await importPins.run(in: context, operatorID: "op")
        #expect(try client("Pat Doe").latitude == 43.1)
        #expect(map.pauses == Array(ImportPins.backoff.prefix(2)))

        try importRows([["Sam Roe", "", "2 Elm St"], ["Lee Poe", "", "4 Pine St"]], at: date.addingTimeInterval(60))
        let busy = FakeMap(["2 Elm St": (1, 1), "4 Pine St": (2, 2)], refusals: 99)
        let stalled = pins(busy)
        await stalled.run(in: context, operatorID: "op")
        // The first is asked until the map has refused too often; the second never.
        #expect(stalled.isWaiting && busy.asked.count == ImportPins.backoff.count + 1)
        #expect(Set(busy.asked).count == 1)
        // Back in front: carries on from the store.
        busy.refusals = 0
        await stalled.run(in: context, operatorID: "op")
        let sam = try client("Sam Roe"), lee = try client("Lee Poe")
        #expect(sam.latitude == 1 && lee.latitude == 2 && !stalled.isWaiting)
        #expect(stalled.done == 2 && stalled.total == 2)
    }

    // A long list: spaced under the map's limit.
    @Test func lookupsAreSpaced() async throws {
        try importRows([["A", "", "1 A St"], ["B", "", "2 B St"], ["C", "", "3 C St"]])
        let map = FakeMap(["1 A St": (1, 1), "2 B St": (2, 2), "3 C St": (3, 3)])
        await pins(map).run(in: context, operatorID: "op")
        #expect(map.pauses == [ImportPins.spacing, ImportPins.spacing])
    }

    // Edited or deleted (and saved) while waiting its turn or while the map
    // answers: left to its screen, or gone, and not listed as a miss.
    @Test(arguments: [true, false])
    func aClientChangedMeanwhileIsntPinnedOrListed(_ mapKnowsIt: Bool) async throws {
        try importRows([["Pat Doe", "", "1 Main St"], ["Sam Roe", "", "2 Elm St"]])
        let pat = try client("Pat Doe"), sam = try client("Sam Roe")
        let map = FakeMap(mapKnowsIt ? ["1 Main St": (1, 1), "2 Elm St": (2, 2)] : [:])
        let importPins = ImportPins(lookUp: { address in
            // While the first lookup is out, its client's address is edited
            // and the other client deleted and saved.
            if map.asked.isEmpty {
                let (looked, other) = address == "1 Main St" ? (pat, sam) : (sam, pat)
                looked.address = "7 New Rd"
                context.delete(other)
                try? context.save()
            }
            return map.lookUp(address)
        }, pause: { _ in })
        await importPins.run(in: context, operatorID: "op")
        let left = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(!AddressPin.exists(latitude: left.latitude, longitude: left.longitude))
        #expect(map.asked.count == 1, "asked \(map.asked)")
        #expect(importPins.notFound.isEmpty)
    }

    // A pin reaches the client's route stops, and a property's.
    @Test func routeStopsFollowTheirPins() async throws {
        try importRows([["Pat Doe", "603-555-0100", "1 Main St"], ["Pat Doe", "603-555-0100", "9 Lake Rd"]])
        let pat = try client("Pat Doe")
        let lake = try #require(pat.properties?.first)
        let route = PlowRoute(name: "Monday", operatorID: "op")
        context.insert(route)
        let home = RouteStop(order: 0, client: pat)
        let away = RouteStop(order: 1, client: pat, place: Place.of(lake))
        for stop in [home, away] {
            context.insert(stop)
            stop.route = route
        }
        try context.save()
        await pins(FakeMap(["1 Main St": (1, 1), "9 Lake Rd": (2, 2)])).run(in: context, operatorID: "op")
        #expect(home.latitude == 1 && away.latitude == 2)
    }

    // Delete Account or Remove from This Device mid-run: it stops at once,
    // and doesn't start again when the app comes back, only for an import.
    @Test func stopHoldsUntilAnImport() async throws {
        try importRows([["Pat Doe", "", "1 Main St"], ["Sam Roe", "", "2 Elm St"]])
        let map = FakeMap(["1 Main St": (1, 1), "2 Elm St": (2, 2)])
        var importPins: ImportPins?
        importPins = ImportPins(lookUp: { address in
            importPins?.stop()
            return map.lookUp(address)
        }, pause: { _ in })
        let stopping = try #require(importPins)
        await stopping.run(in: context, operatorID: "op")
        #expect(map.asked.count == 1 && stopping.total == 0 && stopping.notFound.isEmpty)
        let pat = try client("Pat Doe"), sam = try client("Sam Roe")
        #expect(pat.latitude == 0 && sam.latitude == 0)

        let after = pins(map)
        after.stop()
        await after.run(in: context, operatorID: "op")                      // the app back in front
        #expect(map.asked.count == 1)
        await after.startAfterImport(in: context, operatorID: "op")
        #expect(map.asked.count == 3 && pat.latitude == 1)
    }

    // A second import while the first's pins are being looked up: its
    // clients are looked up once the first run ends.
    @Test func anImportDuringARunIsPinnedAfterIt() async throws {
        try importRows([["Pat Doe", "", "1 Main St"]])
        let map = FakeMap(["1 Main St": (1, 1), "2 Elm St": (2, 2)])
        var importPins: ImportPins?
        importPins = ImportPins(lookUp: { address in
            if address == "1 Main St", let running = importPins {
                // The second import, and its start, while Pat's lookup is out.
                _ = try? self.importRows([["Sam Roe", "", "2 Elm St"]], at: self.date.addingTimeInterval(60))
                Task { await running.startAfterImport(in: self.context, operatorID: "op") }
                await Task.yield()
            }
            return map.lookUp(address)
        }, pause: { _ in })
        let running = try #require(importPins)
        await running.run(in: context, operatorID: "op")
        #expect(map.asked == ["1 Main St", "2 Elm St"])
        let sam = try client("Sam Roe")
        #expect(sam.latitude == 2 && running.total == 2 && running.done == 2)
    }

    // Each import's pins carry on after a relaunch, found from the store.
    @Test func whatsWaitingIsFoundFromTheStore() throws {
        try importRows([["Pat Doe", "603-555-0100", "1 Main St"], ["Pat Doe", "603-555-0100", "9 Lake Rd"]])
        let pinned = Client(name: "Kim Coe", phone: "", address: "5 Ash St", operatorID: "op")
        pinned.tags = [ClientImport.tagPrefix + "Sep 1 at 9:00 AM"]
        pinned.latitude = 1
        context.insert(pinned)
        let pat = try client("Pat Doe")
        let lake = try #require(pat.properties?.first)
        #expect(ImportPins.waiting(in: context, operatorID: "op") == [.client(pat.id), .property(lake.id)])
        #expect(ImportPins.waiting(in: context, operatorID: "someone else").isEmpty)
    }

    // Edited while its lookup was out and left without a pin: looked up
    // again next time, but not counted done twice.
    @Test func doneNeverPassesTotal() async throws {
        try importRows([["Pat Doe", "", "1 Main St"]])
        let pat = try client("Pat Doe")
        let map = FakeMap([:])
        let importPins = ImportPins(lookUp: { address in
            if map.asked.isEmpty { pat.address = "7 New Rd" }
            return map.lookUp(address)
        }, pause: { _ in })
        await importPins.run(in: context, operatorID: "op")
        await importPins.run(in: context, operatorID: "op")
        #expect(map.asked == ["1 Main St", "7 New Rd"])
        #expect(importPins.done == 1 && importPins.total == 1)
    }

    // A shared device: A signs out mid-run and B signs in. A's lookups end,
    // and the run that follows is B's.
    @Test func signingOutEndsTheRunAndTheNextIsTheNewBusinesss() async throws {
        try importRows([["Pat Doe", "", "1 Main St"], ["Ann Coe", "", "3 Ash St"]], operatorID: "a")
        try importRows([["Sam Roe", "", "2 Elm St"]], at: date.addingTimeInterval(60), operatorID: "b")
        let map = FakeMap(["1 Main St": (1, 1), "3 Ash St": (3, 3), "2 Elm St": (2, 2)])
        var importPins: ImportPins?
        importPins = ImportPins(lookUp: { address in
            if map.asked.isEmpty, let running = importPins {
                running.cancelRun()                                          // A signs out
                Task { await running.run(in: self.context, operatorID: "b") }  // B signs in
                await Task.yield()
            }
            return map.lookUp(address)
        }, pause: { _ in })
        let running = try #require(importPins)
        await running.run(in: context, operatorID: "a")
        #expect(map.asked.count == 2 && map.asked.last == "2 Elm St", "asked \(map.asked)")
        let sam = try client("Sam Roe")
        #expect(sam.latitude == 2)
    }

    // What the import screen shows is the signed-in business's: another
    // business's misses and counts don't carry over.
    @Test func anotherBusinessStartsAfresh() async throws {
        try importRows([["Kim Poe", "", "8 Hill St"], ["Lee Poe", "", "0 Nowhere"]], operatorID: "a")
        try importRows([["Sam Roe", "", "2 Elm St"]], at: date.addingTimeInterval(60), operatorID: "b")
        let importPins = pins(FakeMap(["8 Hill St": (8, 8), "2 Elm St": (2, 2)]))
        await importPins.run(in: context, operatorID: "a")
        #expect(importPins.notFound.map(\.name) == ["Lee Poe"] && importPins.done == 2 && importPins.total == 2)
        await importPins.run(in: context, operatorID: "b")
        #expect(importPins.notFound.isEmpty && importPins.done == 1 && importPins.total == 1)
    }
}
