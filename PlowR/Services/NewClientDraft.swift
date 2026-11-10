import Foundation

/// What New Client holds while it's typed: the rules for saving it and for
/// throwing it away live here, not in the screen, so tests can reach them.
nonisolated struct NewClientDraft: Equatable {
    /// Which kind of client this is. A regular customer typed in by hand is
    /// the usual case, so it's the default; only a customer has
    /// `customerSince`, which is what `Pipeline.stage` reads.
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
}
