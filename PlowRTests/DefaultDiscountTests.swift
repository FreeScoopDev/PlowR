import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A client's Default Discount (client page) is every new document's starting
/// discount (Joe, 2026-10-18). It was saved and exported but nothing priced
/// with it, so a 10% client's $400 of work went out as $400. A contract's own
/// price (its installments, a per-visit charge) is what the contract agreed,
/// so it doesn't come off that.
@MainActor
struct DefaultDiscountTests {
    typealias Harness = ActiveRouteStoreTests.Harness
    private let day: TimeInterval = 86_400

    private func line(_ price: Double) -> ProposalLineItem {
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat",
                                    unitPrice: price)
        item.lineTotal = price
        return item
    }

    private func signed(_ h: Harness, _ pricing: Contracts.Pricing, price: String, services: [String]) -> Contract {
        var draft = Contracts.Draft(for: h.client, now: h.clock.addingTimeInterval(-10 * day))
        draft.pricing = pricing
        draft.priceText = price
        draft.serviceIDs = Set(services)
        let contract = Contracts.save(draft, to: nil, of: h.client, in: h.context)
        Contracts.sign(contract, in: h.context, now: h.clock.addingTimeInterval(-10 * day))
        return contract
    }

    private func job(_ h: Harness, _ lines: [(String, Double)]) -> ServiceRecord {
        let record = ServiceRecord(operatorID: "op", sourceKey: "manual:\(UUID().uuidString)", source: .manual)
        record.clientID = h.client.id.uuidString
        record.propertyID = h.client.id.uuidString
        record.performedAt = h.clock.addingTimeInterval(-day)
        record.lines = lines.map { .init(serviceID: $0.0, name: $0.0.capitalized, unitType: "flat", price: $0.1) }
        h.context.insert(record)
        return record
    }

    // MARK: Invoices made for the user

    @Test func aNewDraftInvoiceTakesTheClientsDiscount() throws {
        let h = try Harness(stopCount: 0)
        h.client.defaultDiscountPercent = 10
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(250), line(150)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.discountAmount == 40)
        #expect(invoice.total == 360)
    }

    @Test func theDiscountComesOffBeforeTaxAndToTheCent() throws {
        let h = try Harness(stopCount: 0)
        let profile = BusinessProfile(operatorID: "op")
        profile.defaultTaxRate = 8
        h.context.insert(profile)
        h.client.defaultDiscountPercent = 15
        let invoice = ServiceLog.newDraftInvoice(for: h.client, items: [line(33.33)], operatorID: "op",
                                                 now: h.clock, in: h.context)
        #expect(invoice.discountAmount == 5)                                      // 15% of 33.33 = 4.9995
        #expect(invoice.total == 30.6)                                            // 28.33 + 2.27 tax
    }

    @Test func noDiscountSetOrACompedClientMeansNone() throws {
        let h = try Harness(stopCount: 0)
        let none = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                              now: h.clock, in: h.context)
        #expect(none.discountAmount == 0 && none.total == 100)
        // Comped hides the choice on the client page; a value left from before isn't used.
        h.client.defaultDiscountPercent = 20
        h.client.isComped = true
        let comped = ServiceLog.newDraftInvoice(for: h.client, items: [line(100)], operatorID: "op",
                                                now: h.clock, in: h.context)
        #expect(comped.discountAmount == 0)
    }

    @Test func billUnbilledWorkTakesTheClientsDiscount() throws {
        let h = try Harness(stopCount: 0)
        h.client.defaultDiscountPercent = 10
        _ = job(h, [("mow", 250)])
        _ = job(h, [("mow", 150)])
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.subtotal == 400 && invoice.total == 360)
    }

    @Test func aPerVisitContractsPriceIsNotDiscounted() throws {
        let h = try Harness(stopCount: 0)
        h.client.defaultDiscountPercent = 10
        _ = signed(h, .perVisit, price: "55", services: ["plow"])
        _ = job(h, [("plow", 60), ("salt", 25)])
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.subtotal == 80)                                           // 55 visit + 25 salt
        #expect(invoice.discountAmount == 2.5)                                    // 10% of the salt only
    }

    @Test func recordServicesInvoiceSparesAPerVisitContractsPrice() throws {
        let h = try Harness(stopCount: 0)
        h.client.defaultDiscountPercent = 10
        let contract = signed(h, .perVisit, price: "55", services: ["plow"])
        let services = [StopRecording.Service(id: "plow", name: "Plow", unitType: "flat", pricePerUnit: 60),
                        StopRecording.Service(id: "salt", name: "Salt", unitType: "flat", pricePerUnit: 25)]
        var recording = StopRecording(services: services, zones: [])
        recording.selectedIDs = ["plow", "salt"]
        // The lines and the contract's price both from the recording, as the screen does.
        let lines = recording.invoiceLines(under: contract)
        #expect(lines.map(\.lineTotal) == [55, 25])
        #expect(recording.contractCharge(under: contract) == 55)
        let record = job(h, [("plow", 60), ("salt", 25)])
        let invoice = ServiceLog.invoice(record, lines: lines, contractCharge: recording.contractCharge(under: contract),
                                         client: h.client, operatorID: "op", notes: "", now: h.clock, in: h.context)
        #expect(invoice.discountAmount == 2.5)
        #expect(invoice.total == 77.5)
    }

    @Test func aContractChargeIsOnlyAPerVisitContractsVisit() throws {
        let h = try Harness(stopCount: 0)
        let services = [StopRecording.Service(id: "plow", name: "Plow", unitType: "flat", pricePerUnit: 60),
                        StopRecording.Service(id: "salt", name: "Salt", unitType: "flat", pricePerUnit: 25)]
        var recording = StopRecording(services: services, zones: [])
        recording.selectedIDs = ["salt"]
        let perVisit = signed(h, .perVisit, price: "55", services: ["plow"])
        #expect(recording.contractCharge(under: perVisit) == 0)                   // nothing it covers was done
        #expect(recording.invoiceLines(under: perVisit).map(\.lineTotal) == [25])
        recording.selectedIDs = ["plow"]
        #expect(recording.contractCharge(under: signed(h, .season, price: "900", services: ["plow"])) == 0)
        #expect(recording.contractCharge(under: nil) == 0)
    }

    // The list shows what each invoice will come to before tax.
    @Test func billUnbilledWorkShowsTheDiscountedTotal() throws {
        let h = try Harness(stopCount: 0)
        h.client.defaultDiscountPercent = 10
        _ = signed(h, .perVisit, price: "55", services: ["plow"])
        _ = job(h, [("plow", 60), ("salt", 25)])
        _ = job(h, [("mow", 100)])
        let work = try #require(WorkBilling.unbilledWork(in: nil, operatorID: "op", in: h.context).first)
        #expect(work.subtotal == 180)
        #expect(work.total == 167.5)                                              // 10% of 125, not of 55
        let invoice = try #require(WorkBilling.invoice(work, operatorID: "op", now: h.clock, in: h.context))
        #expect(invoice.discountedTotal == work.total)
    }

    @Test func aContractPaymentIsNotDiscounted() throws {
        let h = try Harness(stopCount: 0)
        h.client.defaultDiscountPercent = 10
        let contract = Contract(name: "Winter", startDate: h.clock, endDate: h.clock.addingTimeInterval(90 * day),
                                operatorID: "op")
        contract.pricingRaw = Contracts.Pricing.season.rawValue
        contract.price = 300
        contract.installments = 1
        contract.clientID = h.client.id.uuidString
        h.context.insert(contract)
        contract.client = h.client
        contract.signedAt = h.clock
        let payment = try #require(ContractInstallments.schedule(of: contract).first)
        let invoice = try #require(ContractInstallments.makeInvoice(for: payment, of: contract, in: h.context,
                                                                     now: h.clock))
        #expect(invoice.discountAmount == 0 && invoice.total == 300)
    }

    // MARK: The builder

    private func draft(_ discount: String, percent: Double, prices: [String]) -> DocumentDraft {
        DocumentDraft(services: [], zones: [],
                      customLines: prices.enumerated().map { .init(name: "Line \($0.offset)", amount: $0.element) },
                      discount: discount, taxRate: "", clientDiscountPercent: percent,
                      locale: Locale(identifier: "en_US"))
    }

    @Test func theBuildersDiscountFollowsTheLinesUntilOneIsTyped() {
        #expect(draft("", percent: 10, prices: ["100"]).discountAmount == 10)
        #expect(draft("", percent: 10, prices: ["100", "300"]).discountAmount == 40)   // follows the subtotal
        #expect(draft("25", percent: 10, prices: ["100", "300"]).discountAmount == 25) // typed wins
        #expect(draft("0", percent: 10, prices: ["100"]).discountAmount == 0)          // 0 means none
        #expect(draft(" ", percent: 10, prices: ["100"]).discountAmount == 10)
        #expect(draft("", percent: 0, prices: ["100"]).discountAmount == 0)
        #expect(draft("", percent: 10, prices: ["400"]).total == 360)
    }

    @Test func theSavedDocumentMatchesTheEstimate() throws {
        let h = try Harness(stopCount: 0)
        let draft = draft("", percent: 25, prices: ["120", "80"])
        let proposal = Proposal(operatorID: "op", client: h.client)
        h.context.insert(proposal)
        draft.apply(to: proposal, grouped: false)
        #expect(proposal.discountAmount == 50)
        #expect(proposal.total == draft.total)
    }

    @Test func theClientPagesChoiceWinsUnlessComped() {
        #expect(DocumentDraft.clientDiscountPercent(onScreen: 15, saved: 5, comped: false) == 15)
        #expect(DocumentDraft.clientDiscountPercent(onScreen: nil, saved: 5, comped: false) == 5)
        #expect(DocumentDraft.clientDiscountPercent(onScreen: 15, saved: 5, comped: true) == 0)
        // The client page just turned Comped off, unsaved: the builder passes the page's switch.
        let page = DocumentDraft.clientDiscountPercent(onScreen: 10, saved: 0, comped: false)
        #expect(page == 10)
        #expect(DocumentDraft.clientDiscountPercent(onScreen: 150, saved: 0, comped: false) == 100)
        #expect(DocumentDraft.clientDiscountPercent(onScreen: -5, saved: 0, comped: false) == 0)
        #expect(DocumentDraft.clientDiscount(subtotal: -20, percent: 10) == 0)
    }
}
