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

    /// A document shared to someone (`isSend`): its client is awaiting a
    /// response. Not for a paid invoice: that's a receipt, nothing is owed.
    static func shared(_ proposal: Proposal, in context: ModelContext, now: Date = .now) {
        guard proposal.invoiceStatus != .paid else { return }
        awaitResponse(clientID: proposal.clientID, in: context, now: now)
    }

    /// Whether finishing the share sheet with `activity` sent the document
    /// to someone: Messages, Mail, AirDrop or another app. Copying, printing
    /// or keeping it (Photos, Files, Notes, Books, a cloud drive...) isn't.
    nonisolated static func isSend(_ activity: UIActivity.ActivityType?) -> Bool {
        guard let activity else { return false }
        let id = activity.rawValue.lowercased()
        return !notSending.contains(activity.rawValue) && !keepingApps.contains { id.hasPrefix($0) }
    }

    nonisolated static let notSending: Set<String> = [
        UIActivity.ActivityType.copyToPasteboard.rawValue,
        UIActivity.ActivityType.print.rawValue,
        UIActivity.ActivityType.saveToCameraRoll.rawValue,
        UIActivity.ActivityType.addToReadingList.rawValue,
        UIActivity.ActivityType.assignToContact.rawValue,
        UIActivity.ActivityType.markupAsPDF.rawValue,
        UIActivity.ActivityType.openInIBooks.rawValue,
        UIActivity.ActivityType.sharePlay.rawValue,
        UIActivity.ActivityType.collaborationCopyLink.rawValue,
    ]

    /// Apps that keep the file rather than send it, by the start of their
    /// share extensions' IDs (lowercased).
    nonisolated static let keepingApps = [
        "com.apple.documentmanageruicore",   // Save to Files
        "com.apple.clouddocsui",             // iCloud Drive
        "com.apple.mobilenotes",             // Notes
        "com.apple.reminders",
        "com.apple.freeform",
        "com.apple.ibooks",                  // Books
        "com.apple.shortcuts",
        "com.getdropbox.",
        "com.google.drive",
        "com.microsoft.skydrive",            // OneDrive
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
    /// starts clear and only documents set it. Kept where an invoice marked
    /// sent explains it: another device with this version already marked it.
    static func clearTextStamps(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: textStampsClearedKey),
              let clients = try? context.fetch(FetchDescriptor<Client>()),
              let documents = try? context.fetch(FetchDescriptor<Proposal>()) else { return }
        for client in clients where client.lastMessageSentAt != nil || client.clientRespondedAt != nil {
            let id = client.id.uuidString
            if let stamp = client.lastMessageSentAt, documents.contains(where: {
                $0.clientID == id && $0.invoiceSentAt.map { abs($0.timeIntervalSince(stamp)) < 1 } == true
            }) { continue }
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
