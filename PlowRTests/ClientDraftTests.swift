//
//  ClientDraftTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Leaving Edit Client asks first only when something would be lost: the
/// screen's fields against the client as saved (ClientDraft).
@MainActor
struct ClientDraftTests {
    /// Kept: a container that goes away resets its context, and every model
    /// in it is destroyed.
    let container: ModelContainer
    let pat: Client

    init() throws {
        container = try ModelContainer(
            for: Client.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        pat = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
        pat.email = "pat@example.com"
        pat.skipNotificationPrompt = true
        pat.goalMinutes = 20
        pat.defaultStopNotes = "Gate code 1234"
        pat.preferredPayment = "check"
        pat.isComped = true
        pat.defaultDiscountPercent = 5
        pat.tags = ["Residential"]
        pat.notes = "Dog in the yard"
        pat.isActive = false
        pat.expectedServiceIDs = ["a", "b"]
        container.mainContext.insert(pat)
    }

    // Each field comes from its own on the client.
    @Test func aDraftIsTheClientAsSaved() {
        let draft = ClientDraft(pat)
        #expect(draft == ClientDraft(
            name: "Pat Doe", phone: "555-0100", email: "pat@example.com", address: "1 Main St",
            skipNotificationPrompt: true, goalMinutes: 20, defaultStopNotes: "Gate code 1234",
            preferredPayment: "check", isComped: true, defaultDiscountPercent: 5, tags: ["Residential"],
            notes: "Dog in the yard", isActive: false, expectedServiceIDs: ["a", "b"]))
    }

    // Every field the screen edits counts as a change.
    @Test func eachEditCounts() {
        let saved = ClientDraft(pat)
        let edits: [(String, (inout ClientDraft) -> Void)] = [
            ("name", { $0.name = "Pat Smith" }),
            ("phone", { $0.phone = "555-0199" }),
            ("email", { $0.email = "" }),
            ("address", { $0.address = "2 Elm St" }),
            ("arrival prompt", { $0.skipNotificationPrompt.toggle() }),
            ("goal", { $0.goalMinutes = 15 }),
            ("stop notes", { $0.defaultStopNotes = "" }),
            ("payment", { $0.preferredPayment = "cash" }),
            ("comped", { $0.isComped.toggle() }),
            ("discount", { $0.defaultDiscountPercent = 10 }),
            ("tags", { $0.tags.append("Priority") }),
            ("notes", { $0.notes = "" }),
            ("active", { $0.isActive.toggle() }),
            ("services", { $0.expectedServiceIDs.insert("c") })
        ]
        for (label, edit) in edits {
            var draft = saved
            edit(&draft)
            #expect(draft != saved, "\(label)")
        }
    }

    // Services ticked in another order aren't a change, and neither is an
    // edit once saved.
    @Test func reorderedOrSavedIsNoChange() {
        var draft = ClientDraft(pat)
        pat.expectedServiceIDs = ["b", "a"]
        #expect(draft == ClientDraft(pat))
        draft.name = "Pat Smith"
        #expect(draft != ClientDraft(pat))
        pat.name = "Pat Smith"                                // Save wrote it
        #expect(draft == ClientDraft(pat))
    }
}
