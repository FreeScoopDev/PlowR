import Foundation
import SwiftData
import SwiftUI
import UIKit

/// An invoice or proposal sent to its client: from then the client shows
/// "Awaiting Response" on their page, until the business taps Mark
/// Responded. An invoice is sent with Mark Sent; any document, by sharing
/// its PDF to someone from the share sheet (Messages, Mail, AirDrop...).
///
/// A text sent from the client's page used to set it, and sending a
/// document didn't. Texts don't set it now.
enum DocumentSent {
    /// Marks an invoice sent now: when, a due date 30 days out if it has
    /// none, and its client awaiting a response. The one place for it: the
    /// document, the documents list, the edit screen and the route's service
    /// recorder all mark invoices sent.
    static func markSent(_ proposal: Proposal, in context: ModelContext, now: Date = .now) {
        proposal.invoiceSentAt = now
        if proposal.invoiceDueDate == nil {
            proposal.invoiceDueDate = now.addingTimeInterval(30 * 86_400)
        }
        awaitResponse(clientID: proposal.clientID, in: context, now: now)
    }

    /// Whether finishing the share sheet with `activity` sent the document
    /// to someone. Copying, printing or saving it isn't sending it.
    nonisolated static func isSend(_ activity: UIActivity.ActivityType?) -> Bool {
        guard let activity else { return false }
        return !notSending.contains(activity.rawValue)
    }

    nonisolated static let notSending: Set<String> = [
        UIActivity.ActivityType.copyToPasteboard.rawValue,
        UIActivity.ActivityType.print.rawValue,
        UIActivity.ActivityType.saveToCameraRoll.rawValue,
        UIActivity.ActivityType.addToReadingList.rawValue,
        UIActivity.ActivityType.assignToContact.rawValue,
        UIActivity.ActivityType.markupAsPDF.rawValue,
        "com.apple.DocumentManagerUICore.SaveToFiles",
        "com.apple.CloudDocsUI.AddToiCloudDrive",
    ]

    /// The client with `clientID` is awaiting a response.
    static func awaitResponse(clientID: String, in context: ModelContext, now: Date = .now) {
        // Match by UUID: a #Predicate on `id` clashes with SwiftData's own id.
        guard let client = try? context.fetch(FetchDescriptor<Client>())
            .first(where: { $0.id.uuidString == clientID }) else { return }
        client.lastMessageSentAt = now
        client.clientRespondedAt = nil
    }

    static let textStampsClearedKey = "awaitingResponseTextStampsCleared"

    /// Once, at the first launch of this version: "Awaiting Response" set by
    /// texts from a client's page would now read as a document sent, so it
    /// starts clear and only documents set it.
    static func clearTextStamps(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: textStampsClearedKey),
              let clients = try? context.fetch(FetchDescriptor<Client>()) else { return }
        for client in clients where client.lastMessageSentAt != nil || client.clientRespondedAt != nil {
            client.lastMessageSentAt = nil
            client.clientRespondedAt = nil
        }
        try? context.save()
        defaults.set(true, forKey: textStampsClearedKey)
    }
}

/// The share sheet for a document's PDF. A share that sends it to someone
/// (DocumentSent.isSend) calls `onSent`.
struct DocumentShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onSent: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            guard completed, DocumentSent.isSend(activity) else { return }
            DispatchQueue.main.async { onSent() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
