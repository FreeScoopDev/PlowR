import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The client search shared by the Clients list and every client picker.
struct ClientSearchTests {
    private func finds(_ typed: String, name: String = "Ellen Park", address: String = "7 Alder Ct",
                       phone: String = "555-0142", tags: [String] = ["Weekly"]) -> Bool {
        ClientSearch.matches(typed, name: name, address: address, phone: phone, tags: tags)
    }

    // Every word must be found, each anywhere: "park alder" is the name
    // and the street.
    @Test func everyWordMustBeFoundSomewhere() {
        #expect(finds("park alder"))
        #expect(finds("Alder  ellen"))
        #expect(finds("weekly 0142"))
        #expect(!finds("park birch"))
        #expect(!finds("ellen jones"))
    }

    @Test func accentsAndCapitalsDontMatter() {
        #expect(finds("jose", name: "José Ruiz"))
        #expect(finds("JOSÉ", name: "Jose Ruiz"))
        #expect(finds("cote", address: "12 Côte Rd"))
    }

    // A number typed without the phone's dashes or brackets still finds it.
    @Test func phoneDigitsMatchWithoutPunctuation() {
        #expect(finds("5550142"))
        #expect(finds("(555) 0142"))
        #expect(finds("5550142", phone: "(555) 014-2"))
        #expect(!finds("5550143"))
        // Digits alone don't search the other fields with their punctuation taken out.
        #expect(!finds("70", address: "7 Alder Ct", phone: ""))
    }

    @Test func noSearchFindsEveryone() {
        #expect(finds(""))
        #expect(finds("  \n"))
        #expect(ClientSearch.words(" a  b ") == ["a", "b"])
    }

    // Add Stops looks in a place's own name and address too.
    @Test func extraFieldsAreSearched() {
        let client = Client(name: "Ellen Park", phone: "", address: "7 Alder Ct", operatorID: "op")
        #expect(!ClientSearch.matches(client, query: "cabin"))
        #expect(ClientSearch.matches(client, query: "park cabin", also: ["Lake Cabin", "1 Shore Rd"]))
    }

    @Test func filterKeepsTheGivenOrder() {
        let clients = ["Cy Alder", "Ann Birch", "Bo Alder"].map {
            Client(name: $0, phone: "", address: "", operatorID: "op")
        }
        #expect(ClientSearch.filter(clients, query: "alder").map(\.name) == ["Cy Alder", "Bo Alder"])
        #expect(ClientSearch.filter(clients, query: " ").count == 3)
    }
}

/// Search and sort on the Documents list.
@MainActor
struct DocumentListTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func key(_ n: Int, created: Double = 0, due: Double? = nil, amount: Double = 0,
                     client: String = "") -> (Int, DocumentList.Key) {
        (n, DocumentList.Key(createdAt: base.addingTimeInterval(created * day),
                             due: due.map { base.addingTimeInterval($0 * day) },
                             amount: amount, clientName: client,
                             id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID()))
    }

    private func order(_ items: [(Int, DocumentList.Key)], _ sort: DocumentSort) -> [Int] {
        DocumentList.ordered(items, by: sort) { $0.1 }.map(\.0)
    }

    @Test func searchFindsClientNumberAndNotes() {
        func finds(_ typed: String) -> Bool {
            DocumentList.matches(typed, clientName: "Renée Park", number: "INV-1042",
                                 notes: "Spring cleanup, back beds")
        }
        #expect(finds("renee"))
        #expect(finds("inv-1042"))
        #expect(finds("1042 park"))
        #expect(finds("cleanup"))
        #expect(!finds("park fall"))
        #expect(finds(""))
    }

    @Test func dueDateSoonestFirstWithNoDueDateLast() {
        let items = [key(1, created: 5), key(2, created: 1, due: 9), key(3, created: 2, due: 3), key(4, created: 3)]
        #expect(order(items, .dueDate) == [3, 2, 1, 4])
    }

    @Test func amountLargestFirst() {
        let items = [key(1, amount: 50), key(2, amount: 900.5), key(3, amount: 0), key(4, amount: 120)]
        #expect(order(items, .amount) == [2, 4, 1, 3])
    }

    @Test func clientAToZIgnoringCapitals() {
        let items = [key(1, client: "zed"), key(2, client: "Amy"), key(3, client: "bob"), key(4, client: "Émile")]
        #expect(order(items, .client) == [2, 3, 4, 1])
    }

    // Each comparison option, pinned: names equal but for capitals or
    // accents tie (so fall to the fixed order, lower ID first), and numbers
    // in a name count as numbers.
    @Test func clientNamesTieOnCapitalsAndAccentsAndCountNumbers() {
        #expect(order([key(1, client: "Amy"), key(2, client: "amy")], .client) == [1, 2])
        #expect(order([key(2, client: "amy"), key(1, client: "Amy")], .client) == [1, 2])
        #expect(order([key(1, client: "amy"), key(2, client: "Amy")], .client) == [1, 2])
        #expect(order([key(1, client: "Émile"), key(2, client: "Emile")], .client) == [1, 2])
        #expect(order([key(2, client: "Emile"), key(1, client: "Émile")], .client) == [1, 2])
        #expect(order([key(1, client: "Client 10"), key(2, client: "Client 2")], .client) == [2, 1])
    }

    // Ties fall back to newest made first, then a fixed order, so the
    // list never shuffles.
    @Test func tiesAreNewestFirstThenStable() {
        let amounts = [key(1, created: 1, amount: 10), key(2, created: 3, amount: 10), key(3, created: 2, amount: 10)]
        #expect(order(amounts, .amount) == [2, 3, 1])
        let dues = [key(1, created: 1, due: 4), key(2, created: 2, due: 4), key(3, created: 0), key(4, created: 7)]
        #expect(order(dues, .dueDate) == [2, 1, 4, 3])
        let names = [key(3, client: "Amy"), key(1, client: "amy"), key(2, client: "Amy")]
        #expect(order(names, .client) == [1, 2, 3])
        #expect(order(names.reversed(), .client) == [1, 2, 3])
    }

    // Newest leaves the list as it was before there was a choice.
    @Test func newestKeepsTheGivenOrder() throws {
        let h = try ActiveRouteStoreTests.Harness(stopCount: 0)
        let docs = (0..<3).map { i -> Proposal in
            let doc = Proposal(operatorID: "op", client: h.client)
            doc.createdAt = base.addingTimeInterval(Double(i) * day)
            h.context.insert(doc)
            return doc
        }
        let given = [docs[1], docs[0], docs[2]]
        #expect(DocumentList.sorted(given, by: .newest).map(\.id) == given.map(\.id))
    }

    // The keys come from the document as its row shows it: the total, and a
    // due date only on an invoice.
    @Test func keysReadTheDocument() throws {
        let h = try ActiveRouteStoreTests.Harness(stopCount: 0)
        func document(invoice: Bool, total: Double, due: Double?) -> Proposal {
            let doc = Proposal(operatorID: "op", client: h.client)
            if invoice { doc.invoiceNumber = "INV-\(Int(total))" }
            doc.invoiceDueDate = due.map { base.addingTimeInterval($0 * day) }
            let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
            h.context.insert(item)
            h.context.insert(doc)
            doc.lineItems = [item]
            return doc
        }
        let small = document(invoice: true, total: 40, due: 2)
        let large = document(invoice: true, total: 300, due: 8)
        let quote = document(invoice: false, total: 999, due: 1)
        #expect(DocumentList.key(quote).due == nil)
        #expect(DocumentList.sorted([small, large, quote], by: .amount).map(\.id) == [quote, large, small].map(\.id))
        #expect(DocumentList.sorted([quote, large, small], by: .dueDate).map(\.id) == [small, large, quote].map(\.id))
    }

    @Test func emptyStatesMatchTheFilter() {
        typealias Filter = ProposalListView.FilterStatus
        #expect(Filter.invoices.emptyState.title == "No Invoices Yet")
        #expect(Filter.invoices.emptyState.startsInvoice == true)
        #expect(Filter.proposals.emptyState.title == "No Proposals Yet")
        #expect(Filter.proposals.emptyState.startsInvoice == false)
        #expect(Filter.draft.emptyState.startsInvoice == true)
        #expect(Filter.overdue.emptyState.startsInvoice == nil)
        #expect(!Filter.invoices.emptyState.message.localizedCaseInsensitiveContains("proposal"))
    }
}
