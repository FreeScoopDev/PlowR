import Foundation
import SwiftData

/// An invoice or proposal marked sent: from then its client shows "Awaiting
/// Response" on their page, until the business taps Mark Responded.
///
/// A text sent from the client's page used to set it, and marking a document
/// sent didn't. It's meant for documents; texts, including the route's,
/// don't set it.
enum DocumentSent {
    /// `proposal`'s client is awaiting a response to it.
    static func awaitResponse(to proposal: Proposal, in context: ModelContext, now: Date = .now) {
        let clientID = proposal.clientID
        // Match by UUID: a #Predicate on `id` clashes with SwiftData's own id.
        guard let client = try? context.fetch(FetchDescriptor<Client>())
            .first(where: { $0.id.uuidString == clientID }) else { return }
        client.lastMessageSentAt = now
        client.clientRespondedAt = nil
    }
}
