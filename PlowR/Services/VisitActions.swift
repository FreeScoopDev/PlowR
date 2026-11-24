import Foundation
import SwiftData

/// What the visit sheet (VisitSheet) offers for a visit, and why anything
/// else isn't there: the one rule book, worked out from plain facts so it's
/// tested without a view. Recording and billing go through the paths Complete
/// and a route stop already use (`ServiceLog.complete`,
/// `ServiceLog.saveVisitRecording`, `ServiceLog.invoice`); this only decides
/// which buttons show.
struct VisitActions: Equatable {
    enum Action: Hashable {
        /// `ServiceLog.complete`, as Schedule's swipe.
        case complete
        /// Record Services for the visit (its expected services ticked).
        case recordServices
        /// The same sheet for a record that exists.
        case editServices
        /// Record Services that saves, completes and drafts the invoice.
        case completeAndInvoice
        /// The same, for a completed visit's unbilled work.
        case invoiceWork
        /// Opens the invoice the work is on. Never gated.
        case viewInvoice
        case editVisit
        case openClient
    }

    /// What the sheet knows about the visit, read once (`facts(for:client:in:)`).
    struct Facts: Equatable {
        var status: VisitStatus
        /// The client is on file (not deleted, not a visit without one).
        var hasClient: Bool
        var clientName: String
        var clientIsActive: Bool
        var clientIsComped: Bool
        /// The visit's `visit:<id>` record exists.
        var hasRecord: Bool
        var recordHasLines: Bool
        /// The record's billing (`ServiceLog.billingStatus`), nil without one.
        var recordBilling: ServiceLog.BillingStatus?
        /// The invoice the visit's work is on: the visit's own
        /// (`ServiceLog.invoice(ofVisit:)`, which must exist), else the
        /// record's. Its number; nil when unbilled.
        var invoiceNumber: String?
        /// `access.canEdit`.
        var canEdit: Bool
    }

    /// The actions, in the order the sheet lists them.
    var actions: [Action]
    /// Why an action a visit can have isn't there.
    var reasons: [String]
    /// The one copper button, if any.
    var primary: Action?
    /// Said on the sheet, not a reason: an inactive client's visit works as usual.
    var inactiveNote: String?
    /// Read only: the actions show, and are run through `ProGate.edit`.
    var needsPro: Bool
    /// "View Invoice <number>".
    var invoiceNumber: String?

    init(_ facts: Facts) {
        var actions: [Action] = []
        var reasons: [String] = []
        let billed = facts.invoiceNumber != nil
        switch (facts.status, facts.hasClient) {
        case (.skipped, _), (.cancelled, _):
            let word = facts.status == .skipped ? "skipped" : "cancelled"
            reasons.append("This visit was \(word), so there's nothing to record or bill.")
        case (.scheduled, false):
            actions.append(.complete)
            reasons.append(Self.noClientReason)
        case (.completed, false):
            reasons.append(Self.noClientReason)
        case (.scheduled, true):
            actions += [.complete, .recordServices]
            if billed {
                actions.append(.viewInvoice)
            } else if facts.clientIsComped {
                reasons.append(Self.compedReason(facts.clientName))
            } else {
                actions.append(.completeAndInvoice)
            }
        case (.completed, true):
            actions.append(facts.hasRecord ? .editServices : .recordServices)
            if billed {
                actions.append(.viewInvoice)
            } else if facts.hasRecord {
                if facts.recordHasLines, facts.recordBilling == .notBilled {
                    actions.append(.invoiceWork)
                } else if let reason = Self.notBillableReason(facts) {
                    reasons.append(reason)
                }
            }
        }
        actions.append(.editVisit)
        if facts.hasClient { actions.append(.openClient) }

        self.actions = actions
        self.reasons = reasons
        primary = actions.contains(.complete) ? .complete
            : actions.contains(.completeAndInvoice) ? .completeAndInvoice : nil
        inactiveNote = facts.hasClient && !facts.clientIsActive ? "\(facts.clientName) is inactive." : nil
        needsPro = !facts.canEdit
        invoiceNumber = facts.invoiceNumber
    }

    static let noClientReason = "No client on file, so there's nothing to record or bill."

    static func compedReason(_ name: String) -> String {
        "\(name) is comped, so their work isn't billed."
    }

    /// Why a completed visit's record can't be invoiced from here.
    private static func notBillableReason(_ facts: Facts) -> String? {
        if !facts.recordHasLines { return "No services recorded yet, so there's nothing to bill." }
        switch facts.recordBilling {
        case .noCharge: return facts.clientIsComped ? compedReason(facts.clientName) : "This work is marked no charge."
        case .covered: return "A contract covers this work, so it isn't billed by the visit."
        case .notTracked: return "This work is from before the Service Log, so its billing isn't tracked."
        case .invoiced, .notBilled, nil: return nil
        }
    }

    /// Whether `action` asks `ProGate.edit` first (read only). Viewing never does.
    func isGated(_ action: Action) -> Bool {
        guard needsPro else { return false }
        switch action {
        case .viewInvoice, .openClient, .editVisit: return false
        case .complete, .recordServices, .editServices, .completeAndInvoice, .invoiceWork: return true
        }
    }

    /// The button's title.
    func title(of action: Action) -> String {
        switch action {
        case .complete: return "Complete"
        case .recordServices: return "Record Services"
        case .editServices: return "Edit Services"
        case .completeAndInvoice: return "Complete & Invoice"
        case .invoiceWork: return "Invoice Work"
        case .viewInvoice: return invoiceNumber.map { "View Invoice \($0)" } ?? "View Invoice"
        case .editVisit: return "Edit Visit"
        case .openClient: return "Open Client"
        }
    }
}

extension VisitActions {
    /// The facts for `visit` as the store has them now.
    @MainActor
    static func facts(for visit: ScheduledVisit, client: Client?, canEdit: Bool,
                      in context: ModelContext) -> Facts {
        let record = ServiceLog.record(forKey: ServiceLog.visitKey(visit.id), in: context)
        let invoice = ServiceLog.invoice(ofVisit: visit, in: context)
            ?? record.flatMap { ServiceLog.invoice(of: $0, in: context) }
        return Facts(status: visit.status, hasClient: client != nil, clientName: client?.name ?? visit.clientName,
                     clientIsActive: client?.isActive ?? true, clientIsComped: client?.isComped ?? false,
                     hasRecord: record != nil, recordHasLines: !(record?.lines.isEmpty ?? true),
                     recordBilling: record.map { ServiceLog.billingStatus(of: $0, in: context) },
                     invoiceNumber: invoice?.invoiceNumber, canEdit: canEdit)
    }
}
