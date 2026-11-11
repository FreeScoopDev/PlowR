//
//  NewClientDraftTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// New Client's rules: which kind of client is saved, what Save needs, and
/// when leaving asks first.
@MainActor
struct NewClientDraftTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    @Test func existingCustomerIsTheDefault() {
        #expect(NewClientDraft().kind == .existingCustomer)
    }

    @Test func anExistingCustomerGetsCustomerSinceInWholeSeconds() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000.75)
        var draft = NewClientDraft()
        draft.kind = .existingCustomer
        #expect(draft.customerSince(at: now) == Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    @Test func aNewLeadHasNoCustomerSince() {
        var draft = NewClientDraft()
        draft.kind = .newLead
        #expect(draft.customerSince(at: .now) == nil)
    }

    @Test func stageFollowsTheKindChosen() throws {
        let h = try Harness(stopCount: 0)
        var draft = NewClientDraft()
        let customer = Client(name: "Cust", phone: "", address: "", operatorID: "op")
        customer.customerSince = draft.customerSince(at: .now)
        draft.kind = .newLead
        let lead = Client(name: "Lead", phone: "", address: "", operatorID: "op")
        lead.customerSince = draft.customerSince(at: .now)
        h.context.insert(customer)
        h.context.insert(lead)
        let facts = Pipeline.Facts(in: h.context)
        #expect(Pipeline.stage(of: customer, facts: facts) == .customer)
        #expect(Pipeline.stage(of: lead, facts: facts) == .lead)
    }

    @Test func aNameAloneCanBeSaved() {
        var draft = NewClientDraft()
        draft.name = "Pat"
        #expect(draft.canSave)
    }

    @Test func aBlankOrSpacesNameCannotBeSaved() {
        var draft = NewClientDraft()
        #expect(!draft.canSave)
        draft.name = "   \n "
        draft.phone = "555-0100"
        #expect(!draft.canSave)
    }

    @Test func editClientCanSaveWithoutAPhoneButNotWithoutAName() throws {
        let h = try Harness(stopCount: 0)
        let client = Client(name: "Pat", phone: "", address: "", operatorID: "op")
        h.context.insert(client)
        var draft = ClientDraft(client)
        #expect(draft.canSave)
        draft.name = "  "
        #expect(!draft.canSave)
    }

    @Test func leavingAsksOnlyWhenSomethingIsTyped() {
        var draft = NewClientDraft()
        #expect(!draft.hasTypedWork)
        draft.kind = .newLead
        #expect(!draft.hasTypedWork)
        draft.name = "  "
        #expect(!draft.hasTypedWork)
        for set in [\NewClientDraft.name, \.phone, \.email, \.address, \.routeNotes] {
            var typed = NewClientDraft()
            typed[keyPath: set] = "x"
            #expect(typed.hasTypedWork)
        }
    }

    // MARK: What is saved

    @Test func theSavedClientCarriesTheKindTheNotesAndTidyText() throws {
        let h = try Harness(stopCount: 0)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000.75)
        var draft = NewClientDraft()
        draft.name = "  Ellen Park "
        draft.phone = "   "
        draft.email = " ellen@example.com "
        draft.address = " 7 Alder Ct "
        draft.routeNotes = "Gate code 4411\n"

        let customer = draft.makeClient(operatorID: "op", now: now)
        #expect(customer.name == "Ellen Park")
        #expect(customer.phone.isEmpty)
        #expect(customer.email == "ellen@example.com")
        #expect(customer.address == "7 Alder Ct")
        #expect(customer.defaultStopNotes == "Gate code 4411")   // Route Notes, not the private notes
        #expect(customer.notes.isEmpty)
        #expect(customer.operatorID == "op")
        #expect(customer.customerSince == Date(timeIntervalSinceReferenceDate: 800_000_000))

        draft.kind = .newLead
        let lead = draft.makeClient(operatorID: "op", now: now)
        #expect(lead.customerSince == nil)

        h.context.insert(customer)
        h.context.insert(lead)
        let facts = Pipeline.Facts(in: h.context)
        #expect(Pipeline.stage(of: customer, facts: facts) == .customer)
        #expect(Pipeline.stage(of: lead, facts: facts) == .lead)
    }

    // New Client's Notes (its placeholder says "Gate code, dog in the yard")
    // went to the private notes, which no route shows: a gate code typed there
    // never reached the stop. They're Route Notes now.
    @Test func aNewClientsNoteShowsAtTheirStop() throws {
        let h = try Harness(stopCount: 0)
        var draft = NewClientDraft()
        draft.name = "Ellen Park"
        draft.address = "7 Alder Ct"
        draft.routeNotes = "Gate code 4411"
        let client = draft.makeClient(operatorID: "op", now: .now)
        h.context.insert(client)
        let stop = RouteStop(order: 0, client: client, place: Place.main(of: client))
        #expect(stop.placeNotes == "Gate code 4411")
        #expect(stop.hasNotesToShow)
        client.defaultStopNotes = "Gate code 9900"
        #expect(ClientStops.follow(stop, client))
        #expect(stop.placeNotes == "Gate code 9900")
    }

    @Test func theFormCanOpenOnNewLead() {
        #expect(NewClientDraft(kind: .newLead).kind == .newLead)
        #expect(NewClientDraft(kind: .newLead).makeClient(operatorID: "op", now: .now).customerSince == nil)
    }
}
