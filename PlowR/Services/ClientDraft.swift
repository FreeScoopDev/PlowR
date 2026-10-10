import Foundation

/// What Edit Client edits: the screen holds one, so leaving can tell whether
/// anything would be lost (it differs from the client as saved), and Save
/// writes it back in one place. A pin moved on the pin screen isn't here:
/// that screen saves it itself. No field has a default, so a new one can't
/// be left out of `init(_ client:)` without the compiler saying so.
nonisolated struct ClientDraft: Equatable {
    var name: String
    var phone: String
    var email: String
    var address: String
    var skipNotificationPrompt: Bool
    var goalMinutes: Int
    var defaultStopNotes: String
    var preferredPayment: String
    var isComped: Bool
    var taxExempt: Bool
    var defaultDiscountPercent: Double
    var tags: [String]
    var notes: String
    var isActive: Bool
    /// A set: the order they were ticked in isn't a change.
    var expectedServiceIDs: Set<String>

    /// A client needs a name and a phone number: Save isn't offered without
    /// them, from the toolbar or from Back's prompt.
    var canSave: Bool { !name.isEmpty && !phone.isEmpty }

    /// The screen's fields after the client changed underneath it, from
    /// `old` to `new`: Schedule making an inactive client active, or an edit
    /// synced from another device. A field the screen hadn't changed takes
    /// the new value; one it had changed keeps the screen's. An untouched
    /// screen used to look edited, and its Save wrote the old values back.
    func rebased(from old: ClientDraft, to new: ClientDraft) -> ClientDraft {
        var next = self
        func follow<T: Equatable>(_ field: WritableKeyPath<ClientDraft, T>) {
            if self[keyPath: field] == old[keyPath: field] { next[keyPath: field] = new[keyPath: field] }
        }
        follow(\.name)
        follow(\.phone)
        follow(\.email)
        follow(\.address)
        follow(\.skipNotificationPrompt)
        follow(\.goalMinutes)
        follow(\.defaultStopNotes)
        follow(\.preferredPayment)
        follow(\.isComped)
        follow(\.taxExempt)
        follow(\.defaultDiscountPercent)
        follow(\.tags)
        follow(\.notes)
        follow(\.isActive)
        follow(\.expectedServiceIDs)
        return next
    }

    /// What Back's prompt says about the screen's changes over `saved`. Save
    /// writes everything but a new address before looking the address up, so
    /// after a failed lookup only the address is left unsaved.
    func unsavedMessage(comparedWith saved: ClientDraft) -> String {
        var rest = self
        rest.address = saved.address
        return rest == saved ? "The new address hasn't been saved."
                             : "Your changes to this client haven't been saved."
    }
}

@MainActor
extension ClientDraft {
    /// The client as saved.
    init(_ client: Client) {
        self.init(name: client.name, phone: client.phone, email: client.email, address: client.address,
                  skipNotificationPrompt: client.skipNotificationPrompt, goalMinutes: client.goalMinutes,
                  defaultStopNotes: client.defaultStopNotes, preferredPayment: client.preferredPayment,
                  isComped: client.isComped, taxExempt: client.taxExempt, defaultDiscountPercent: client.defaultDiscountPercent,
                  tags: client.tags, notes: client.notes, isActive: client.isActive,
                  expectedServiceIDs: Set(client.expectedServiceIDs))
    }

    /// Writes all but the address to `client`. Save handles the address,
    /// which may need looking up first, and marking inactive, which goes
    /// through ClientRemoval.
    func applyExceptAddressAndActive(to client: Client) {
        client.name = name
        client.phone = phone
        client.email = email
        client.skipNotificationPrompt = skipNotificationPrompt
        client.goalMinutes = goalMinutes
        client.defaultStopNotes = defaultStopNotes
        client.preferredPayment = preferredPayment
        client.isComped = isComped
        client.taxExempt = taxExempt
        client.defaultDiscountPercent = defaultDiscountPercent
        client.tags = tags
        client.notes = notes
        client.expectedServiceIDs = Array(expectedServiceIDs)
    }
}
