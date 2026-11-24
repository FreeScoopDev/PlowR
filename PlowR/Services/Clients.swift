import Foundation
import SwiftData

/// Finding a client from what names them.
enum Clients {
    /// The client a quote or invoice is for (its `clientID`), if they're
    /// still there. Matched by UUID: a #Predicate on `id` clashes with
    /// SwiftData's own id. Mark Paid, its Undo and the payment method use it.
    static func of(_ document: Proposal, in context: ModelContext) -> Client? {
        let id = document.clientID
        return ((try? context.fetch(FetchDescriptor<Client>())) ?? []).first { $0.id.uuidString == id }
    }
}
