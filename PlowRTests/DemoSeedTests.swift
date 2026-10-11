//
//  DemoSeedTests.swift
//  PlowRTests
//

#if DEBUG
import Testing
import Foundation
import SwiftData
@testable import PlowR

/// The demo business is what the App Store screenshots are made from, so what
/// it says about itself has to agree with what it holds.
@MainActor
struct DemoSeedTests {

    /// The container, not just its context: a context whose container has gone traps.
    private func seeded(now: Date) throws -> ModelContainer {
        let container = try ModelContainer(for: Schema(PlowRApp.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        DemoLaunch.seed(in: container.mainContext, now: now)
        return container
    }

    @Test func eachClientsTotalsAgreeWithTheirRecords() throws {
        let container = try seeded(now: Date(timeIntervalSince1970: 1_791_700_000))
        let context = container.mainContext
        let clients = try context.fetch(FetchDescriptor<Client>())
        #expect(clients.count == DemoLaunch.sampleClients.count)
        var counts: [Int] = []
        for client in clients {
            let records = ServiceLog.records(ofClient: client.id.uuidString, in: context)
            counts.append(records.count)
            #expect(client.totalVisits == records.count)
            #expect(client.totalServiceMinutes == records.map(\.minutes).reduce(0, +))
            #expect(client.lastServiceDate == records.map(\.performedAt).max())
        }
        #expect(counts.sorted() == [2, 4, 4, 4, 4, 4])
    }

    @Test(arguments: [1_791_700_000.0, 1_795_000_000.0])
    func textsNameTheirInvoiceAndDueDateWhateverTheDay(seconds: Double) throws {
        let container = try seeded(now: Date(timeIntervalSince1970: seconds))
        let context = container.mainContext
        let texts = try context.fetch(FetchDescriptor<SentText>())
        #expect(texts.count == 3)
        #expect(texts.allSatisfy { $0.kind == TextLog.Kind.text.rawValue })
        let invoices = try context.fetch(FetchDescriptor<Proposal>())
        let owed = try #require(invoices.first { $0.invoiceNumber == "INV-0002" })
        let due = try #require(owed.invoiceDueDate).formatted(.dateTime.month(.abbreviated).day())
        let reminder = try #require(texts.first { $0.body.contains("INV-0002") })
        #expect(reminder.body.contains(due))
        #expect(texts.contains { $0.body.contains("INV-0001") })
    }
}
#endif
