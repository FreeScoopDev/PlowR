//
//  AppSearchTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Home's Search (`AppSearch`): one matching rule for every kind, one
/// business's items only, each kind's order, and the five-per-kind cap.
@MainActor
struct AppSearchTests {
    /// An in-memory database with CloudKit off and autosave off.
    @MainActor
    struct Store {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            container = try ModelContainer(
                for: Schema(PlowRApp.models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            )
            context = container.mainContext
            context.autosaveEnabled = false
        }

        func client(_ name: String, address: String = "", operatorID: String = "op",
                    active: Bool = true) -> Client {
            let client = Client(name: name, phone: "", address: address, operatorID: operatorID)
            client.isActive = active
            context.insert(client)
            return client
        }

        func document(for client: Client, number: String = "", notes: String = "",
                      createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
                      operatorID: String = "op") -> Proposal {
            let document = Proposal(operatorID: operatorID, client: client)
            document.invoiceNumber = number
            document.notes = notes
            document.createdAt = createdAt
            context.insert(document)
            return document
        }

        func route(_ name: String, operatorID: String = "op") -> PlowRoute {
            let route = PlowRoute(name: name, operatorID: operatorID)
            context.insert(route)
            return route
        }

        func job(_ clientName: String, address: String = "", notes: String = "",
                 at date: Date = Date(timeIntervalSince1970: 1_800_000_000),
                 operatorID: String = "op") -> ServiceRecord {
            let record = ServiceRecord(operatorID: operatorID, sourceKey: "manual:\(UUID().uuidString)",
                                       source: .manual)
            record.clientName = clientName
            record.propertyAddress = address
            record.notes = notes
            record.performedAt = date
            context.insert(record)
            return record
        }
    }

    private func search(_ typed: String, clients: [Client] = [], documents: [Proposal] = [],
                        routes: [PlowRoute] = [], records: [ServiceRecord] = [],
                        operatorID: String = "op") -> AppSearch.Results {
        AppSearch.results(query: typed, clients: clients, documents: documents, routes: routes,
                          records: records, operatorID: operatorID)
    }

    // MARK: - Matching

    // "maple henderson": the client's name and the job's street, two fields.
    @Test func everyWordMayBeInADifferentField() throws {
        let store = try Store()
        let job = store.job("Henderson", address: "14 Maple St")
        let other = store.job("Henderson", address: "9 Oak Ave")
        let found = search("maple henderson", records: [job, other]).records
        let ids: [UUID] = found.map(\.id)
        #expect(ids == [job.id])
    }

    @Test func accentsAndCapitalsDontMatter() throws {
        let store = try Store()
        let client = store.client("José Côté")
        let route = store.route("ÉCOLE Loop")
        let foundClients = search("jose COTE", clients: [client]).clients
        #expect(foundClients.count == 1)
        let foundRoutes = search("ecole loop", routes: [route]).routes
        #expect(foundRoutes.count == 1)
    }

    // The Documents list's own matcher: an invoice number finds its invoice.
    @Test func aDocumentIsFoundByItsNumber() throws {
        let store = try Store()
        let client = store.client("Henderson")
        let invoice = store.document(for: client, number: "INV-1043")
        let other = store.document(for: client, number: "INV-1044")
        let found = search("1043", documents: [invoice, other]).documents
        let ids: [UUID] = found.map(\.id)
        #expect(ids == [invoice.id])
    }

    @Test func aRouteIsFoundByItsName() throws {
        let store = try Store()
        let north = store.route("North Side")
        let south = store.route("South Side")
        let found = search("north", routes: [north, south]).routes
        let ids: [UUID] = found.map(\.id)
        #expect(ids == [north.id])
    }

    @Test func aJobIsFoundByItsNotes() throws {
        let store = try Store()
        let gate = store.job("Park", notes: "Side gate broken, use the driveway")
        let plain = store.job("Park", notes: "All good")
        let found = search("broken gate", records: [gate, plain]).records
        let ids: [UUID] = found.map(\.id)
        #expect(ids == [gate.id])
    }

    @Test func anotherBusinessesItemsAreLeftOut() throws {
        let store = try Store()
        let mine = store.client("Maple Farm")
        let theirs = store.client("Maple Farm", operatorID: "other")
        let myDoc = store.document(for: mine, number: "INV-7")
        let theirDoc = store.document(for: theirs, number: "INV-7", operatorID: "other")
        let myRoute = store.route("Maple", operatorID: "op")
        let theirRoute = store.route("Maple", operatorID: "other")
        let myJob = store.job("Maple Farm")
        let theirJob = store.job("Maple Farm", operatorID: "other")
        let found = search("maple", clients: [mine, theirs], documents: [myDoc, theirDoc],
                           routes: [myRoute, theirRoute], records: [myJob, theirJob])
        let clientIDs: [UUID] = found.clients.map(\.id)
        let documentIDs: [UUID] = found.documents.map(\.id)
        let routeIDs: [UUID] = found.routes.map(\.id)
        let recordIDs: [UUID] = found.records.map(\.id)
        #expect(clientIDs == [mine.id])
        #expect(documentIDs == [myDoc.id])
        #expect(routeIDs == [myRoute.id])
        #expect(recordIDs == [myJob.id])
    }

    @Test(arguments: ["", "   ", " \n "])
    func noWordsFindNothing(_ typed: String) throws {
        let store = try Store()
        let client = store.client("Henderson")
        let document = store.document(for: client, number: "INV-1")
        let route = store.route("North")
        let job = store.job("Henderson")
        let found = search(typed, clients: [client], documents: [document], routes: [route], records: [job])
        #expect(found.isEmpty)
    }

    // MARK: - Order

    @Test func eachKindHasItsOrder() throws {
        let store = try Store()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let zed = store.client("Zed Park")
        let anna = store.client("anna park", active: false)
        let bob = store.client("Bob Park")
        // Older one's client first by name: a name order would put it first.
        let older = store.document(for: anna, number: "P-1", createdAt: base)
        let newer = store.document(for: bob, number: "P-2", createdAt: base.addingTimeInterval(60))
        let west = store.route("West Park")
        let east = store.route("East Park")
        let lastWeek = store.job("Park", at: base)
        let today = store.job("Park", at: base.addingTimeInterval(7 * 86_400))

        let found = search("park", clients: [zed, anna, bob], documents: [older, newer],
                           routes: [west, east], records: [lastWeek, today])
        let clientIDs: [UUID] = found.clients.map(\.id)
        let documentIDs: [UUID] = found.documents.map(\.id)
        let routeIDs: [UUID] = found.routes.map(\.id)
        let recordIDs: [UUID] = found.records.map(\.id)
        // A to Z, capitals aside, the inactive client included.
        #expect(clientIDs == [anna.id, bob.id, zed.id])
        #expect(documentIDs == [newer.id, older.id])
        #expect(routeIDs == [east.id, west.id])
        #expect(recordIDs == [today.id, lastWeek.id])
    }

    // MARK: - Route stops

    // The route list's words, and its count: while a route runs, this run's
    // stops (one left out today doesn't count).
    @Test func aRoutesStopsAreCountedAsTheRouteListCountsThem() throws {
        let store = try Store()
        let route = store.route("North")
        for index in 0..<3 {
            let stop = RouteStop(order: index, customName: "Stop \(index)")
            stop.route = route
            store.context.insert(stop)
        }
        try store.context.save()
        let defaults = try #require(UserDefaults(suiteName: "AppSearchTests-\(UUID().uuidString)"))
        let routeStore = ActiveRouteStore(defaults: defaults, surfaces: FakeRouteSurfaces())
        let idle = RouteFacts.stopsText(of: route, store: routeStore)
        #expect(idle == "3 stops")
        let skipped = try #require(route.sortedStops.first)
        routeStore.start(route, skipping: [skipped.id])
        let running = RouteFacts.stopsText(of: route, store: routeStore)
        #expect(running == "2 stops")
        let none = RouteFacts.stopsText(0)
        let one = RouteFacts.stopsText(1)
        #expect(none == "No stops yet")
        #expect(one == "1 stop")
    }

    // MARK: - Cap

    @Test func fiveAreShownWithTheFullCountKept() throws {
        let store = try Store()
        let jobs: [ServiceRecord] = (0..<8).map { store.job("Client \($0)", notes: "salt") }
        let found = search("salt", records: jobs).records
        #expect(found.count == 8)
        let shown: [ServiceRecord] = AppSearch.shown(found)
        #expect(shown.count == 5)
        #expect(AppSearch.hasMore(found))
        let five: [ServiceRecord] = Array(jobs.prefix(5))
        #expect(!AppSearch.hasMore(five))
        #expect(AppSearch.shown(five).count == 5)
    }

    // MARK: - Timing (local only, no assertion)

    /// 5,000 of each kind, searched once; prints the time for the PR.
    /// No timing assertion: those are flaky on CI. Runs only when asked
    /// (`TEST_RUNNER_PLOWR_TIMING=1 xcodebuild test …`): 20,000 records
    /// made for nothing on every run would slow the suite.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PLOWR_TIMING"] != nil))
    func searchingFiveThousandOfEach() throws {
        let store = try Store()
        let count = 5_000
        let clients: [Client] = (0..<count).map { store.client("Client \($0)", address: "\($0) Maple St") }
        let documents: [Proposal] = clients.prefix(count).enumerated().map { index, client in
            store.document(for: client, number: "INV-\(index)", notes: "Weekly service")
        }
        let routes: [PlowRoute] = (0..<count).map { store.route("Route \($0)") }
        let records: [ServiceRecord] = (0..<count).map {
            store.job("Client \($0)", address: "\($0) Maple St", notes: "Side gate")
        }
        let clock = ContinuousClock()
        var found = AppSearch.Results()
        let elapsed = clock.measure {
            found = search("maple 12", clients: clients, documents: documents, routes: routes, records: records)
        }
        print("AppSearch: 4 x \(count) records searched in \(elapsed)")
        #expect(!found.clients.isEmpty)
    }
}
