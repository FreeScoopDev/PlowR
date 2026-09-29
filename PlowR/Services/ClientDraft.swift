import Foundation

/// What Edit Client edits, so leaving can tell whether anything would be
/// lost. The screen's fields make one, the client as saved makes another,
/// and they differ while there are unsaved changes. A pin moved on the pin
/// screen isn't here: that screen saves it itself.
nonisolated struct ClientDraft: Equatable {
    var name = ""
    var phone = ""
    var email = ""
    var address = ""
    var skipNotificationPrompt = false
    var goalMinutes = 0
    var defaultStopNotes = ""
    var preferredPayment = ""
    var isComped = false
    var defaultDiscountPercent = 0.0
    var tags: [String] = []
    var notes = ""
    var isActive = true
    /// A set: the order they were ticked in isn't a change.
    var expectedServiceIDs: Set<String> = []
}

extension ClientDraft {
    /// The client as saved.
    init(_ client: Client) {
        self.init(name: client.name, phone: client.phone, email: client.email, address: client.address,
                  skipNotificationPrompt: client.skipNotificationPrompt, goalMinutes: client.goalMinutes,
                  defaultStopNotes: client.defaultStopNotes, preferredPayment: client.preferredPayment,
                  isComped: client.isComped, defaultDiscountPercent: client.defaultDiscountPercent,
                  tags: client.tags, notes: client.notes, isActive: client.isActive,
                  expectedServiceIDs: Set(client.expectedServiceIDs))
    }
}
