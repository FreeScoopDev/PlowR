import Foundation
import SwiftData

/// Texts sent to clients from PlowR, for their Timeline. Every text goes
/// through Messages' composer (MessageComposer), and each screen that opens
/// one records it here once Messages says it was sent: never for a text
/// cancelled or that failed.
enum TextLog {
    enum Kind: String, CaseIterable {
        /// Written in Messages from a client's page or a stop.
        case text
        /// The heads-up to the next client on a route.
        case heading
        /// Message All: one text to several clients on a route.
        case routeMessage
        /// A reminder about an invoice.
        case invoiceReminder

        var title: String {
            switch self {
            case .text: "Text sent"
            case .heading: "Heads-up sent"
            case .routeMessage: "Route message sent"
            case .invoiceReminder: "Invoice reminder sent"
            }
        }
    }

    /// Records a text sent to each of these clients. A stop or recipient
    /// without a client on file (a one-time stop) isn't recorded.
    static func record(_ kind: Kind, body: String, to clientIDs: [UUID], in context: ModelContext,
                       now: Date = .now) {
        guard !clientIDs.isEmpty, let clients = try? context.fetch(FetchDescriptor<Client>()) else { return }
        let byID = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        for id in clientIDs where seen.insert(id).inserted {
            guard let client = byID[id] else { continue }
            let text = SentText(clientID: id.uuidString, kind: kind.rawValue,
                                body: body.trimmingCharacters(in: .whitespacesAndNewlines), sentAt: now)
            text.operatorID = client.operatorID
            text.clientName = client.name
            context.insert(text)
        }
        try? context.save()
    }

    /// A client's texts. (The Timeline puts them in order with everything else.)
    static func texts(ofClient clientID: String, in context: ModelContext) -> [SentText] {
        (try? context.fetch(FetchDescriptor<SentText>(predicate: #Predicate { $0.clientID == clientID }))) ?? []
    }
}
