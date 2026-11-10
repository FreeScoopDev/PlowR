import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Switching a client between lead and customer from their page, and the
/// Contact menu's "has a number to dial" test.
@MainActor
struct ClientKindSwitchTests {
    let context: ModelContext
    let now = Date(timeIntervalSinceReferenceDate: 813_000_000.75)

    init() throws {
        let container = try ModelContainer(for: Schema(PlowRApp.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        context = container.mainContext
    }

    private func client(_ name: String = "Sam") -> Client {
        let client = Client(name: name, phone: "", address: "", operatorID: "op")
        context.insert(client)
        return client
    }

    private func facts() -> Pipeline.Facts { Pipeline.Facts(in: context) }

    private func stage(_ client: Client) -> Pipeline.Stage { Pipeline.stage(of: client, facts: facts(), now: now) }

    private func quote(_ client: Client, at date: Date) {
        let document = Proposal(operatorID: "op", client: client)
        document.createdAt = date
        context.insert(document)
    }

    @Test func markingAsCustomerSetsWholeSecondsAndMakesThemACustomer() throws {
        let sam = client()
        quote(sam, at: now.addingTimeInterval(-100))
        #expect(stage(sam) == .quoted)
        #expect(Pipeline.canMarkAsCustomer(sam, facts: facts(), now: now))
        Pipeline.markAsCustomer(sam, in: context, now: now)
        let since = try #require(sam.customerSince)
        #expect(since == Date(timeIntervalSinceReferenceDate: 813_000_000))
        #expect(stage(sam) == .customer)
        #expect(Pipeline.entries([sam], operatorID: "op", facts: facts(), now: now).isEmpty)
        #expect(!Pipeline.canMarkAsCustomer(sam, facts: facts(), now: now))
        #expect(!context.hasChanges)
    }

    @Test func markAsCustomerIsOfferedToLeadsAndQuotesOnlyWhenActive() {
        let lead = client("Lead")
        #expect(Pipeline.canMarkAsCustomer(lead, facts: facts(), now: now))
        lead.isActive = false
        #expect(!Pipeline.canMarkAsCustomer(lead, facts: facts(), now: now))
        let lost = client("Lost")
        lost.lostAt = now
        #expect(!Pipeline.canMarkAsCustomer(lost, facts: facts(), now: now))
    }

    @Test func markingAsLeadClearsItAndTheyAreALead() {
        let sam = client()
        sam.customerSince = now
        #expect(stage(sam) == .customer)
        #expect(Pipeline.canMarkAsLead(sam, facts: facts(), now: now))
        Pipeline.markAsLead(sam, in: context)
        #expect(sam.customerSince == nil)
        #expect(stage(sam) == .lead)
        #expect(!Pipeline.canMarkAsLead(sam, facts: facts(), now: now))
        #expect(!context.hasChanges)
    }

    @Test func markingAsLeadWithAProposalIsQuoted() {
        let sam = client()
        sam.customerSince = now
        quote(sam, at: now.addingTimeInterval(-100))
        Pipeline.markAsLead(sam, in: context)
        #expect(stage(sam) == .quoted)
    }

    @Test func markingAsLeadAfterBeingMarkedLostIsLost() {
        let sam = client()
        sam.lostAt = now.addingTimeInterval(-50)
        quote(sam, at: now.addingTimeInterval(-100))      // no newer proposal
        sam.customerSince = now.addingTimeInterval(-10)
        #expect(stage(sam) == .customer)
        #expect(Pipeline.canMarkAsLead(sam, facts: facts(), now: now))
        Pipeline.markAsLead(sam, in: context)
        #expect(stage(sam) == .lost)
    }

    @Test func markAsLeadIsNotOfferedToAnInactiveClient() {
        let sam = client()
        sam.customerSince = now
        sam.isActive = false
        #expect(!Pipeline.canMarkAsLead(sam, facts: facts(), now: now))
    }

    @Test func markAsLeadIsNeverOfferedToACustomerByWhatHappened() {
        let visited = client("Visited")
        visited.customerSince = now
        visited.totalVisits = 2
        let routed = client("Routed")
        routed.customerSince = now
        let stop = RouteStop(order: 0, client: routed)
        context.insert(stop)
        let invoiced = client("Invoiced")
        invoiced.customerSince = now
        let invoice = Proposal(operatorID: "op", client: invoiced)
        invoice.invoiceNumber = "INV-0001"
        context.insert(invoice)
        let contracted = client("Contracted")
        contracted.customerSince = now
        let contract = Contract(name: "Season", startDate: now.addingTimeInterval(-86_400),
                                endDate: now.addingTimeInterval(86_400 * 30), operatorID: "op")
        contract.signedAt = contract.startDate
        context.insert(contract)
        contract.client = contracted
        let only = client("Only")
        only.customerSince = now
        let facts = facts()
        for sam in [visited, routed, invoiced, contracted] {
            #expect(Pipeline.stage(of: sam, facts: facts, now: now) == .customer)
            #expect(!Pipeline.canMarkAsLead(sam, facts: facts, now: now), "\(sam.name)")
        }
        #expect(Pipeline.canMarkAsLead(only, facts: facts, now: now))
    }

    @Test func aVisitMakesMarkAsLeadUnavailable() {
        let sam = client()
        sam.customerSince = now
        context.insert(ScheduledVisit(operatorID: "op", clientID: sam.id.uuidString, clientName: sam.name,
                                      clientAddress: "", scheduledDate: now))
        #expect(!Pipeline.canMarkAsLead(sam, facts: facts(), now: now))
    }

    @Test func anImportedCustomerCanBeMarkedAsLeadAndUndoStillTakesThemBack() throws {
        let table = CSVReader.Table(header: ["Name", "Phone", "Address"], rows: [["Sam Roe", "", "2 Elm St"]])
        let preview = ClientImport.preview(table, fields: [.name, .phone, .address], existing: [],
                                           addressesAsProperties: false)
        let result = try ClientImport.save(preview, as: .customers, operatorID: "op", in: context, now: now,
                                           locale: Locale(identifier: "en_US"), timeZone: .gmt)
        let sam = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(sam.customerSince != nil)
        #expect(Pipeline.canMarkAsLead(sam, facts: facts(), now: now))
        Pipeline.markAsLead(sam, in: context)
        #expect(sam.customerSince == nil && stage(sam) == .lead)
        #expect(ClientImport.undoPlan(for: result, in: context).removable.count == 1)
        let plan = try ClientImport.undo(result, in: context)
        #expect(plan.removable.count == 1 && plan.kept == 0)
        #expect(try context.fetchCount(FetchDescriptor<Client>()) == 0)
    }

    @Test func aNumberWithNothingToDialOffersNoCall() {
        #expect(MapLinks.callLink("n/a") == nil)
        #expect(MapLinks.callLink("   ") == nil)
        #expect(MapLinks.callLink("603-555-0100") != nil)
    }
}
