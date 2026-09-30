import Foundation
import SwiftData

/// A text sent to a client from PlowR, kept for their Timeline. Texts go
/// out through Messages, which says only whether one was sent: what's kept
/// is the text as PlowR drafted it (the user could change it in Messages
/// before sending), and when.
@Model
final class SentText {
    var id: UUID = UUID()
    var operatorID: String = ""
    var clientID: String = ""
    /// A copy of the client's name when it was sent.
    var clientName: String = ""
    var sentAt: Date = Date()
    /// What it was (TextLog.Kind): a text, a heads-up from the route, a
    /// message to the whole route, an invoice reminder.
    var kind: String = ""
    /// The text as drafted. Empty for one written in Messages from scratch.
    var body: String = ""

    init(clientID: String, kind: String, body: String, sentAt: Date) {
        self.clientID = clientID
        self.kind = kind
        self.body = body
        self.sentAt = sentAt
    }
}
