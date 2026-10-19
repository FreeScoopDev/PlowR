import SwiftData
import TipKit

/// The schedule and money tips (1.8, B3). Copy in `HelpGuide.json`, rules in
/// `PlowRTips`. Each goes away for good once the user does the thing.

/// Add Visit, by Repeat: visits that recur.
nonisolated struct RepeatVisitTip: PlowRTip {
    static let helpID = "tip-repeat-visit"
    static let visitRepeated = Tips.Event(id: "visitRepeated")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(Self.visitRepeated) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Schedule: a day with three or more visits becomes a route.
nonisolated struct RouteFromDayTip: PlowRTip {
    static let helpID = "tip-route-from-day"
    static let routeMade = Tips.Event(id: "routeMadeFromDay")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(PlowRTips.$dayVisitCount) { $0 >= 3 }
        #Rule(Self.routeMade) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Documents: recorded work not billed yet, billed in one go.
nonisolated struct BillWorkTip: PlowRTip {
    static let helpID = "tip-bill-work"
    static let workBilled = Tips.Event(id: "workBilled")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(PlowRTips.$hasUnbilledWork) { $0 == true }
        #Rule(Self.workBilled) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Documents: an overdue invoice, and the reminder text for it. Not on a
/// Mac (no texting).
nonisolated struct ReminderTip: PlowRTip {
    static let helpID = "tip-reminder"
    static let reminderOpened = Tips.Event(id: "reminderOpened")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$onMac) { $0 == false }
        #Rule(PlowRTips.$hasOverdue) { $0 == true }
        #Rule(Self.reminderOpened) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Documents: an invoice went out with no way to pay printed on it.
nonisolated struct PaymentMethodsTip: PlowRTip {
    static let helpID = "tip-payment-methods"
    static let methodAdded = Tips.Event(id: "paymentMethodAdded")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(PlowRTips.$needsPaymentMethod) { $0 == true }
        #Rule(Self.methodAdded) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

extension PlowRTips {
    /// What the Documents tips wait on, from the screen's documents.
    struct DocumentsState: Equatable {
        var hasOverdue: Bool
        var needsPaymentMethod: Bool
    }

    static func documentsState(invoices: [Proposal], paymentMethods: Int) -> DocumentsState {
        DocumentsState(hasOverdue: invoices.contains { $0.invoiceStatus == .overdue },
                       needsPaymentMethod: paymentMethods == 0 && invoices.contains { $0.isInvoice && $0.invoiceSentAt != nil })
    }
}

nonisolated extension PlowRTips {
    /// Every schedule and money tip, for TipsTests (which fails a PlowRTip not listed).
    static let moneyTipTypes: [any PlowRTip.Type] = [RepeatVisitTip.self, RouteFromDayTip.self, BillWorkTip.self,
                                                     ReminderTip.self, PaymentMethodsTip.self]
    static var moneyTipIDs: [String] { moneyTipTypes.map { $0.helpID } }
}
