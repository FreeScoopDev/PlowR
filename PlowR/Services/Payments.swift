import Foundation
import SwiftData

/// The payments ledger: money received against invoices, in parts or all at
/// once, and the one place that works out what's owed and what came in.
///
/// An invoice used to be paid or not: Mark Paid set `invoicePaidAt`, and
/// every screen that showed money owed added up the unpaid invoices' totals
/// its own way. Now each payment is kept (Payment), an invoice is paid when
/// its payments cover its total (`settle`), and what's owed is each
/// invoice's balance (`Proposal.balanceDue`). `invoicePaidAt` still marks
/// it paid, so a device with an older PlowR agrees on which invoices are.
enum Payments {
    /// Amounts within half a cent are the same amount.
    static let tolerance = 0.005

    // MARK: - Recording

    /// Records `amount` received on `invoice`, never dated in the future.
    /// Nil for nothing (a proposal, an amount not above zero, or more than
    /// is owed: an overpayment isn't a payment of this invoice).
    @discardableResult
    static func record(_ amount: Double, method: String, note: String = "", receivedAt: Date,
                       on invoice: Proposal, in context: ModelContext, now: Date = .now) -> Payment? {
        let amount = InvoiceLines.roundedToCent(amount)
        guard invoice.isInvoice, amount > 0, amount <= invoice.balanceDue + tolerance else { return nil }
        let payment = Payment(amount: amount, method: method, receivedAt: min(receivedAt, now),
                              operatorID: invoice.operatorID)
        payment.clientID = invoice.clientID
        payment.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(payment)
        payment.invoice = invoice
        settle(invoice, in: context)
        return payment
    }

    /// Mark Paid: the balance received now, by the client's usual method.
    /// An invoice with nothing owed (a zero total) is simply marked paid.
    static func payInFull(_ invoice: Proposal, in context: ModelContext, now: Date = .now) {
        guard invoice.isInvoice, invoice.invoicePaidAt == nil else { return }
        let balance = invoice.balanceDue
        guard balance > 0 else {
            DocumentSent.markPaid(invoice, in: context, now: now)
            return
        }
        record(balance, method: preferredMethod(for: invoice, in: context), receivedAt: now, on: invoice,
               in: context, now: now)
    }

    /// Takes a payment back (recorded by mistake). What it paid is owed
    /// again, if the payments were what made it paid: one marked paid in
    /// full some other way (Mark Paid on an older PlowR) stays paid.
    static func delete(_ payment: Payment, in context: ModelContext) {
        let invoice = payment.invoice
        let paidByPayments = invoice.map { covered($0) } ?? false
        payment.invoice = nil
        context.delete(payment)
        guard let invoice, invoice.invoicePaidAt == nil || paidByPayments else { return }
        if live(invoice).isEmpty {
            invoice.invoicePaidAt = nil
        } else {
            settle(invoice, in: context)
        }
    }

    /// Paid once its payments cover its total, on the day the last one
    /// came; owed again if they no longer do (a payment taken back, the
    /// invoice edited up). An invoice with no payments is left as it is:
    /// one marked paid before payments were kept stays paid.
    static func settle(_ invoice: Proposal, in context: ModelContext) {
        let payments = live(invoice)
        guard invoice.isInvoice, let last = payments.map(\.receivedAt).max() else { return }
        let paid = InvoiceLines.roundedToCent(payments.reduce(0) { $0 + $1.amount })
        if paid + tolerance >= invoice.total {
            if invoice.invoicePaidAt == nil {
                // A payment is the client's response (DocumentSent.markPaid).
                DocumentSent.markPaid(invoice, in: context, now: last)
            } else {
                invoice.invoicePaidAt = last
            }
        } else {
            invoice.invoicePaidAt = nil
        }
    }

    /// Every sent invoice not marked paid whose payments now cover it: the
    /// parts recorded on two devices, each short of the total, meet here
    /// once iCloud brings them together, and no screen settled them. Run at
    /// launch, when iCloud brings changes, and when the app comes back.
    /// A draft is left alone: an older PlowR's Reset to Draft keeps its
    /// payments, and marking it paid would undo that. Saves only if one
    /// changed.
    static func settleAll(in context: ModelContext) {
        guard let invoices = try? context.fetch(FetchDescriptor<Proposal>(
            predicate: #Predicate { $0.invoicePaidAt == nil && $0.invoiceSentAt != nil })) else { return }
        var changed = false
        for invoice in invoices where invoice.isInvoice && !live(invoice).isEmpty {
            settle(invoice, in: context)
            changed = changed || invoice.invoicePaidAt != nil
        }
        if changed { try? context.save() }
    }

    private static func live(_ invoice: Proposal) -> [Payment] {
        (invoice.payments ?? []).filter { !$0.isDeleted && $0.modelContext != nil }
    }

    private static func covered(_ invoice: Proposal) -> Bool {
        let payments = live(invoice)
        return !payments.isEmpty
            && InvoiceLines.roundedToCent(payments.reduce(0) { $0 + $1.amount }) + tolerance >= invoice.total
    }

    // MARK: - Methods

    /// What a payment can be recorded as: the usual ones, then the
    /// business's own payment methods (Venmo, PayPal...), then Other.
    static func methods(_ paymentMethods: [PaymentMethod]) -> [String] {
        let own = paymentMethods.filter(\.isActive).sorted { $0.sortOrder < $1.sortOrder }.map(\.label)
        var seen = Set<String>()
        return (["Cash", "Check", "Card", "Zelle"] + own + ["Bank Transfer", "Other"]).filter {
            let key = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    /// How the invoice's client usually pays, as a method's name.
    static func preferredMethod(for invoice: Proposal, in context: ModelContext) -> String {
        let id = invoice.clientID
        let preferred = ((try? context.fetch(FetchDescriptor<Client>())) ?? [])
            .first { $0.id.uuidString == id }?.preferredPayment ?? ""
        return method(forPreferred: preferred)
    }

    /// The client's Preferred Payment (Edit Client) as a method's name.
    static func method(forPreferred preferred: String) -> String {
        switch preferred {
        case "cash": "Cash"
        case "check": "Check"
        case "zelle": "Zelle"
        case "card": "Card"
        default: ""
        }
    }

    // MARK: - Money owed and received

    /// Invoices whose payments come to more than their total, the oldest
    /// first: most likely one payment recorded on two devices before they
    /// synced (the app refuses an overpayment on one device). Their extra
    /// counts as received until it's removed, so the Dashboard points to them.
    static func overpaid(_ documents: [Proposal]) -> [Proposal] {
        documents.filter { $0.isInvoice && $0.voidedAt == nil && $0.overpaid > 0 }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// What's owed across `documents`: each invoice's balance.
    static func owed(_ documents: [Proposal]) -> Double {
        InvoiceLines.roundedToCent(documents.reduce(0) { $0 + $1.balanceDue })
    }

    /// What's been received across `documents`: every receipt, so it's
    /// the same money the months add up to.
    static func received(_ documents: [Proposal]) -> Double {
        InvoiceLines.roundedToCent(receipts(documents).reduce(0) { $0 + $1.amount })
    }

    /// Money received, each amount on the day it came: every payment, and a
    /// paid invoice's rest on the day it was marked paid (all of it, for
    /// one paid before payments were kept). For money in by month.
    static func receipts(_ documents: [Proposal]) -> [(date: Date, amount: Double)] {
        documents.filter(\.isInvoice).flatMap { invoice -> [(date: Date, amount: Double)] in
            let payments = invoice.sortedPayments
            var receipts = payments.map { (date: $0.receivedAt, amount: $0.amount) }
            // A voided invoice's "paid" went to its revision as a payment
            // (ServiceLog.movePayments): only its own payments count here.
            if let paidAt = invoice.invoicePaidAt, invoice.voidedAt == nil {
                let rest = InvoiceLines.roundedToCent(invoice.total - payments.reduce(0) { $0 + $1.amount })
                if rest > tolerance { receipts.append((paidAt, rest)) }
            }
            return receipts
        }
    }

    /// A month's money: what came in during it, and what's still owed on
    /// invoices sent (or made) in it.
    struct Month: Equatable {
        let start: Date
        var received: Double = 0
        var owed: Double = 0
    }

    /// The last `limit` months with any money, newest first. Money counts in
    /// the month it came, so an invoice paid in parts adds to each month a
    /// part came in. (It used to count whole invoices in the month they were
    /// paid, and a partly paid one as owed in full.)
    static func byMonth(_ documents: [Proposal], limit: Int = 12, calendar: Calendar = .current) -> [Month] {
        var months: [Date: Month] = [:]
        func start(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)?.start ?? date }
        for receipt in receipts(documents) {
            let key = start(receipt.date)
            months[key, default: Month(start: key)].received += receipt.amount
        }
        for invoice in documents where invoice.balanceDue > 0 {
            let key = start(invoice.invoiceSentAt ?? invoice.createdAt)
            months[key, default: Month(start: key)].owed += invoice.balanceDue
        }
        return months.values
            .map { Month(start: $0.start, received: InvoiceLines.roundedToCent($0.received),
                         owed: InvoiceLines.roundedToCent($0.owed)) }
            .sorted { $0.start > $1.start }
            .prefix(limit).map { $0 }
    }
}
