import Foundation

/// What New Client holds while it's typed: the rules for saving it and for
/// throwing it away live here, not in the screen, so tests can reach them.
nonisolated struct NewClientDraft: Equatable {
    /// Which kind of client this is. A regular customer typed in by hand is
    /// the usual case, so it's the default; only a customer has
    /// `customerSince`, which is what `Pipeline.stage` reads. Nothing clears
    /// `customerSince` later, so a screen that adds someone to quote them
    /// (Documents) opens the form on New Lead: saved as a customer, they'd
    /// never be Quoted, followed up or markable as lost.
    enum Kind: String, CaseIterable, Identifiable {
        case existingCustomer = "Existing Customer"
        case newLead = "New Lead"
        var id: String { rawValue }
    }

    var kind: Kind = .existingCustomer
    var name = ""
    var phone = ""
    var email = ""
    var address = ""
    var notes = ""

    /// Only a name is needed (a blank one, or spaces, isn't one).
    var canSave: Bool { ClientDraft.hasName(name) }

    /// Whether any field has text: leaving then asks first. The kind alone
    /// isn't typed work.
    var hasTypedWork: Bool {
        [name, phone, email, address, notes].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The client's `customerSince` when saved at `now`: whole seconds, as
    /// the spreadsheet import writes it. A lead has none.
    func customerSince(at now: Date) -> Date? {
        switch kind {
        case .existingCustomer: return Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down))
        case .newLead: return nil
        }
    }

    /// The client this draft saves as, at `now`: the one place the form's
    /// fields become a client, so a test can check that the kind, the notes
    /// and the rest really reach it. Text is kept without the spaces around
    /// it: a phone of only spaces would otherwise pass every "has a number"
    /// check and offer a text to nobody.
    @MainActor
    func makeClient(operatorID: String, now: Date) -> Client {
        func tidy(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let client = Client(name: tidy(name), phone: tidy(phone), address: tidy(address), operatorID: operatorID)
        client.email = tidy(email)
        client.notes = tidy(notes)
        client.customerSince = customerSince(at: now)
        return client
    }
}
