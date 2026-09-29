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

    // Save writes back every field it edits (but the address, looked up
    // first, and active, which goes through ClientRemoval).
    @Test func saveWritesEveryField() {
        let draft = ClientDraft(
            name: "Pat Smith", phone: "555-0199", email: "", address: pat.address,
            skipNotificationPrompt: false, goalMinutes: 15, defaultStopNotes: "",
            preferredPayment: "cash", isComped: false, defaultDiscountPercent: 10, tags: ["Priority"],
            notes: "", isActive: pat.isActive, expectedServiceIDs: ["c"])
        draft.applyExceptAddressAndActive(to: pat)
        #expect(ClientDraft(pat) == draft)
        var moved = draft
        moved.address = "2 Elm St"
        moved.isActive.toggle()
        moved.applyExceptAddressAndActive(to: pat)
        #expect(pat.address == "1 Main St")
        #expect(pat.isActive == draft.isActive)
    }

    // A client needs a name and a phone number to be saved, from Back's
    // prompt as from the toolbar.
    @Test func saveNeedsANameAndAPhone() {
        var draft = ClientDraft(pat)
        #expect(draft.canSave)
        draft.phone = ""
        #expect(!draft.canSave)
        draft.phone = "555-0100"
        draft.name = ""
        #expect(!draft.canSave)
    }

    // The client changed underneath (Schedule reactivating them, a synced
    // edit): what the screen hadn't touched follows; what it had, stays.
    @Test func fieldsNotEditedFollowTheClient() {
        let old = ClientDraft(pat)
        var new = old
        new.name = "Pat Smith"; new.phone = "555-0199"; new.email = ""; new.address = "2 Elm St"
        new.skipNotificationPrompt.toggle(); new.goalMinutes = 30; new.defaultStopNotes = ""
        new.preferredPayment = "zelle"; new.isComped.toggle(); new.defaultDiscountPercent = 0
        new.tags = []; new.notes = ""; new.isActive.toggle(); new.expectedServiceIDs = ["z"]
        #expect(old.rebased(from: old, to: new) == new)        // untouched: no false prompt
        var edited = old
        edited.notes = "Mine"
        let rebased = edited.rebased(from: old, to: new)
        #expect(rebased.notes == "Mine")                         // kept, still to save
        #expect(rebased.isActive == new.isActive)                // followed
        #expect(rebased != new)
    }

    // After a failed lookup everything but the new address is saved, and
    // Back's prompt says so.
    @Test func thePromptSaysWhatIsntSaved() {
        let saved = ClientDraft(pat)
        var draft = saved
        draft.address = "2 Elm St"
        #expect(draft.unsavedMessage(comparedWith: saved) == "The new address hasn't been saved.")
        draft.notes = ""
        #expect(draft.unsavedMessage(comparedWith: saved) == "Your changes to this client haven't been saved.")
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
