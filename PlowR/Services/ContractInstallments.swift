import Foundation
import SwiftData

/// What a contract bills by its own schedule. A season price is split into
/// its payments, one a month from the start; a monthly contract bills each
/// month through its end; a per-visit one bills its visits instead (Bill
/// Unbilled Work). On each payment's date the Dashboard and the contract's
/// page show it due, with Make Invoice: one tap makes its draft invoice,
/// to be sent like any other. Nothing is sent by itself.
///
/// The drafts aren't made in the background. Several devices on one iCloud
/// account each making them, each before it had heard of the others', made
/// copies, and cleaning those up could delete one already sent. So a draft
/// is only ever made by a person, on the device in their hand.
enum ContractInstallments {
    struct Installment: Equatable, Identifiable {
        /// 1, 2, …
        let index: Int
        let date: Date
        let amount: Double
        var id: Int { index }
    }

    /// Its payments, worked out from its terms. A season price's are equal
    /// to the cent, the last taking what's left. Once it's signed they
    /// don't move, except that a monthly contract's end can (not before
    /// today), which adds or drops months still to come.
    static func schedule(of contract: Contract, calendar: Calendar = .current) -> [Installment] {
        let start = calendar.startOfDay(for: contract.startDate)
        let end = calendar.startOfDay(for: contract.endDate)
        // Each month counted from the start, not from the month before: the
        // 31st stays the 31st (or the month's last day), not the 28th.
        func month(_ k: Int) -> Date? { calendar.date(byAdding: .month, value: k, to: start) }
        switch Contracts.pricing(of: contract) {
        case .perVisit:
            return []
        case .season:
            let count = max(1, contract.installments)
            let cents = Int((contract.price * 100).rounded())
            let share = cents / count
            return (0..<count).compactMap { k in
                guard let date = month(k) else { return nil }
                let amount = k == count - 1 ? cents - share * (count - 1) : share
                return Installment(index: k + 1, date: date, amount: Double(amount) / 100)
            }
        case .monthly:
            var installments: [Installment] = []
            var k = 0
            while let date = month(k), date <= end, k < 120 {
                installments.append(Installment(index: k + 1, date: date, amount: contract.price))
                k += 1
            }
            return installments
        }
    }

    /// What its invoice line says: "Winter 2026–27, payment 2 of 3", or
    /// "Lawn Care, April 2027".
    static func title(of installment: Installment, in contract: Contract, calendar: Calendar = .current) -> String {
        switch Contracts.pricing(of: contract) {
        case .monthly:
            var month = Date.FormatStyle.dateTime.month(.wide).year()
            month.timeZone = calendar.timeZone
            return "\(contract.name), \(installment.date.formatted(month))"
        default:
            return contract.installments > 1
                ? "\(contract.name), payment \(installment.index) of \(contract.installments)"
                : contract.name
        }
    }

    /// The payments whose date has come and whose invoice hasn't been made:
    /// signed, the client still on file, and (cancelled) only those dated
    /// up to the day it was.
    static func due(_ contract: Contract, now: Date, calendar: Calendar = .current) -> [Installment] {
        guard contract.signedAt != nil, contract.client != nil else { return [] }
        let today = calendar.startOfDay(for: now)
        let cancelled = contract.cancelledAt.map { calendar.startOfDay(for: $0) }
        return schedule(of: contract, calendar: calendar).filter { installment in
            installment.date <= today && !contract.installmentsMade.contains(installment.index)
                && (cancelled.map { installment.date <= $0 } ?? true)
        }
    }

    /// Every payment due across this business's contracts.
    static func allDue(_ contracts: [Contract], operatorID: String, now: Date = .now, calendar: Calendar = .current)
        -> [(contract: Contract, installment: Installment)] {
        contracts.filter { $0.operatorID == operatorID }
            .flatMap { contract in due(contract, now: now, calendar: calendar).map { (contract, $0) } }
    }

    /// Makes the draft invoice for `installment` (Make Invoice). Its due date
    /// is set when it's sent (DocumentSent.markSent), counted from then: it
    /// may wait a while as a draft.
    @discardableResult
    static func makeInvoice(for installment: Installment, of contract: Contract, in context: ModelContext,
                            now: Date = .now, calendar: Calendar = .current) -> Proposal? {
        guard let client = contract.client, !contract.installmentsMade.contains(installment.index) else { return nil }
        let item = ProposalLineItem(serviceName: title(of: installment, in: contract, calendar: calendar), zoneLabel: "",
                                    quantity: 1, unitType: "flat", unitPrice: installment.amount, sortOrder: 0, itemNotes: "")
        item.lineTotal = installment.amount
        let invoice = ServiceLog.newDraftInvoice(for: client, items: [item], operatorID: contract.operatorID,
                                                now: now, in: context)
        invoice.invoiceDueDate = nil
        invoice.contractID = contract.id.uuidString
        invoice.installmentIndex = installment.index
        contract.installmentsMade.append(installment.index)
        try? context.save()
        return invoice
    }

    /// Makes every payment's draft that's due (the Dashboard's Make Invoices).
    @discardableResult
    static func makeAllDue(operatorID: String, in context: ModelContext, now: Date = .now) -> [Proposal] {
        allDue(Contracts.all(in: context), operatorID: operatorID, now: now).compactMap {
            makeInvoice(for: $0.installment, of: $0.contract, in: context, now: now)
        }
    }

    /// Each payment and its invoice, if made (its latest revision, if
    /// revised), for the contract's page.
    static func ledger(of contract: Contract, in context: ModelContext, calendar: Calendar = .current)
        -> [(installment: Installment, invoice: Proposal?)] {
        let id = contract.id.uuidString
        let invoices = (try? context.fetch(FetchDescriptor<Proposal>(predicate: #Predicate { $0.contractID == id }))) ?? []
        return schedule(of: contract, calendar: calendar).map { installment in
            (installment, invoices.filter { $0.installmentIndex == installment.index }
                .max { $0.createdAt < $1.createdAt })
        }
    }

    /// Whether another live invoice bills the same contract payment. Two
    /// devices can each make a payment's invoice before iCloud brings the
    /// other's (Make Invoices on both), and the client would be billed
    /// twice. PlowR doesn't remove either by itself: the other device may
    /// have sent its copy or recorded a payment on it by the time it syncs
    /// (#88 found the same of copied visits). Each copy's page says so, and
    /// so does the Dashboard (`duplicates`), so the business deletes or
    /// voids one. Live means not void: a revision is its payment's live
    /// invoice (its original is void), a plain void gives the payment back.
    static func hasDuplicate(_ invoice: Proposal, among all: [Proposal]) -> Bool {
        isLiveBilling(invoice) && otherInvoice(billing: invoice, among: all) != nil
    }

    /// Another live invoice of the same contract payment as `invoice` (which
    /// may itself be void by now): the copy a banner links to, and what keeps
    /// a voided copy from giving the payment back while another still bills it.
    static func otherInvoice(billing invoice: Proposal, among all: [Proposal]) -> Proposal? {
        guard invoice.isInvoice, !invoice.contractID.isEmpty, invoice.installmentIndex > 0 else { return nil }
        return all.first { $0.id != invoice.id && isLiveBilling($0) && paymentKey($0) == paymentKey(invoice) }
    }

    /// What the banner on `invoice` says to do about `other`: take back the
    /// copy no money came in on, so a client who paid isn't asked again.
    static func duplicateAdvice(for invoice: Proposal, other: Proposal) -> String {
        let lead = "Another invoice also bills this contract payment: they were made on two devices before they synced."
        func paid(_ p: Proposal) -> Bool { p.paymentsTotal > Payments.tolerance || p.invoicePaidAt != nil }
        switch (paid(invoice), paid(other)) {
        case (true, false):
            return "\(lead) This one has a payment: delete or void the other one."
        case (false, true):
            return "\(lead) The other one has a payment: delete or void this one."
        default:
            return "\(lead) Delete one that wasn't sent (swipe it in Documents), or void one."
        }
    }

    /// One invoice of each contract payment billed more than once, the
    /// oldest first: for the Dashboard to point to.
    static func duplicates(_ documents: [Proposal], operatorID: String) -> [Proposal] {
        let live = documents.filter { $0.operatorID == operatorID && isLiveBilling($0) }
        return Dictionary(grouping: live) { paymentKey($0) }.values
            .filter { $0.count > 1 }
            .compactMap { $0.min { $0.createdAt < $1.createdAt } }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private static func isLiveBilling(_ invoice: Proposal) -> Bool {
        invoice.isInvoice && !invoice.isDeleted && !invoice.contractID.isEmpty && invoice.installmentIndex > 0
            && invoice.voidedAt == nil
    }

    private static func paymentKey(_ invoice: Proposal) -> String {
        "\(invoice.contractID)\u{1F}\(invoice.installmentIndex)"
    }

    /// Contract invoices made and not sent yet.
    static func readyToSend(_ documents: [Proposal], operatorID: String) -> [Proposal] {
        documents.filter { $0.operatorID == operatorID && !$0.contractID.isEmpty && $0.invoiceStatus == .draft }
    }
}
