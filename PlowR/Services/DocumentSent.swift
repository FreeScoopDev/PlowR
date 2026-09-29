import Foundation
import SwiftData
import SwiftUI
import UIKit

/// An invoice or proposal sent to its client: from then the client shows
/// "Awaiting Response" on their page, until the business taps Mark
/// Responded. An invoice is sent with Mark Sent; any document, by sharing
/// its PDF to someone from the share sheet (Messages, Mail, AirDrop...)
/// with its Mark as Sent switch on (DocumentShareView).
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

    /// A document shared to someone (`isSend`) with the share sheet's Mark as
    /// Sent switch on (`toClient`): its client is awaiting a response, and a
    /// draft invoice is sent (Joe's call: it used to stay a draft, with no
    /// due date). With the switch off, a copy that isn't going to the client
    /// (to a partner, an accountant, the business's own files), nothing
    /// changes (Joe's call too). Nor for a paid invoice (shareCanMark).
    static func shared(_ proposal: Proposal, toClient: Bool, in context: ModelContext, now: Date = .now) {
        guard toClient, shareCanMark(proposal.invoiceStatus) else { return }
        if proposal.invoiceStatus == .draft {
            markSent(proposal, in: context, now: now)
        } else {
            awaitResponse(clientID: proposal.clientID, in: context, now: now)
        }
    }

    /// The builder's preview shared a document not saved yet. Sent to the
    /// client (`toClient`), its client is awaiting a response now, and the
    /// builder saves it as shared (true; saveBuilt), which marks an invoice
    /// sent. A copy that isn't going to the client changes nothing.
    static func sharedBeforeSave(clientID: String, toClient: Bool, in context: ModelContext,
                                 now: Date = .now) -> Bool {
        guard toClient else { return false }
        awaitResponse(clientID: clientID, in: context, now: now)
        return true
    }

    /// Whether sharing a document with `status` can mark anything: every one
    /// but a paid invoice, a receipt, with nothing owed or awaited. The share
    /// sheet shows its Mark as Sent switch only then.
    nonisolated static func shareCanMark(_ status: InvoiceStatus) -> Bool {
        status != .paid
    }

    /// What the share sheet says its Mark as Sent switch does, for a document
    /// with `status` going (or, switched off, not going) to `clientName`.
    nonisolated static func shareNote(status: InvoiceStatus, clientName: String, toClient: Bool) -> String {
        let who = clientName.isEmpty ? "the client" : clientName
        guard toClient else { return "For a copy that isn't going to \(who): nothing is marked" }
        return status == .draft ? "Sharing it marks the invoice sent and \(who) as Awaiting Response"
                                : "Sharing it marks \(who) as Awaiting Response"
    }

    /// Marks an invoice paid now. A payment is the client's response, so it
    /// ends "Awaiting Response" (Joe's call).
    static func markPaid(_ proposal: Proposal, in context: ModelContext, now: Date = .now) {
        proposal.invoicePaidAt = now
        let id = proposal.clientID
        guard let client = try? context.fetch(FetchDescriptor<Client>()).first(where: { $0.id.uuidString == id }),
              client.lastMessageSentAt != nil else { return }
        client.clientRespondedAt = now
    }

    /// Whether a document the builder saves is the one its preview shared:
    /// the same document (going back to the form builds a new one), still
    /// with the number the client saw (saving renumbers it if another
    /// invoice took that number meanwhile). Only then is it saved as shared.
    static func wasSharedBeforeSave(_ proposal: Proposal, sharedID: UUID?, sharedNumber: String) -> Bool {
        proposal.id == sharedID && proposal.invoiceNumber == sharedNumber
    }

    /// Saves a document the builder made; `sharedID` and `sharedNumber` are
    /// what its preview shared to the client (sharedBeforeSave), if anything.
    /// In this order: the invoice's
    /// number is confirmed before it's inserted (inserted, it would count as
    /// taking its own number), and whether it's the one shared is decided
    /// after, since a renumbered invoice isn't the one the client has.
    static func saveBuilt(_ proposal: Proposal, sharedID: UUID?, sharedNumber: String,
                          in context: ModelContext, now: Date = .now) {
        // Numbered when built, so the preview shows it. If another invoice has
        // taken that number since (synced from another device), take the next.
        if proposal.isInvoice {
            proposal.invoiceNumber = InvoiceNumbering.confirmed(proposal.invoiceNumber,
                                                                operatorID: proposal.operatorID, in: context)
        }
        // Insert items first so the cascade inverse relationship doesn't double-insert them
        for item in (proposal.lineItems ?? []) { context.insert(item) }
        proposal.lineItems = proposal.lineItems   // re-affirm relationship after explicit inserts
        context.insert(proposal)
        if wasSharedBeforeSave(proposal, sharedID: sharedID, sharedNumber: sharedNumber) {
            shared(proposal, toClient: true, in: context, now: now)
        }
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
        "com.apple.uikit.activity.remoteopeninapplication",   // opening it in another app (Preview, Books...)
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

/// Sharing a document's PDF: the system share sheet, under a Mark as Sent
/// switch (Joe's call). On, as sharing always was, a share that sends the
/// PDF to someone marks it sent to the client (DocumentSent.shared); off,
/// for a copy that isn't going to the client, nothing is marked. It starts
/// on every time. A paid invoice, which sharing never marks, has no switch.
struct DocumentShareView: View {
    let url: URL
    let status: InvoiceStatus
    let clientName: String
    /// A share that sent the PDF to someone, and whether the switch was on.
    let onSent: (_ toClient: Bool) -> Void
    @State private var toClient = true

    var body: some View {
        VStack(spacing: 0) {
            if DocumentSent.shareCanMark(status) {
                Toggle(isOn: $toClient) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mark as Sent")
                        Text(DocumentSent.shareNote(status: status, clientName: clientName, toClient: toClient))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            DocumentShareSheet(url: url) { onSent(toClient) }
        }
    }
}

/// The system share sheet for a document's PDF. A share that sends it to
/// someone (DocumentSent.isSend) calls `onSent`.
struct DocumentShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onSent: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        handleCompletion(of: controller)
        return controller
    }

    /// The latest `onSent`: it reads the Mark as Sent switch.
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        handleCompletion(of: controller)
    }

    private func handleCompletion(of controller: UIActivityViewController) {
        let onSent = onSent
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            guard completed, DocumentSent.isSend(activity) else { return }
            DispatchQueue.main.async { onSent() }
        }
    }
}
