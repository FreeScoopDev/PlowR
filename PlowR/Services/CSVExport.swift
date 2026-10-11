import Foundation
import SwiftData

/// The business's data as spreadsheet files (CSV): clients, invoices and the
/// Service History, for an accountant, for importing elsewhere, or to keep.
/// Money is plain numbers with two decimals and dates are year-month-day, so
/// a spreadsheet reads them as numbers and dates.
enum CSVExport {
    /// A cell: text is guarded against being run as a formula; numbers and
    /// dates are written as they are.
    enum Cell {
        case text(String)
        case plain(String)
    }

    /// A whole file: a header row, then the rows, with CRLF line endings
    /// (RFC 4180) and a byte-order mark so Excel reads accents correctly.
    static func document(header: [String], rows: [[Cell]]) -> String {
        let lines = [header.map { escape($0) }] + rows.map { row in row.map { render($0) } }
        return "\u{FEFF}" + lines.map { $0.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func render(_ cell: Cell) -> String {
        switch cell {
        case .text(let text): escape(neutralized(text))
        case .plain(let value): escape(value)
        }
    }

    /// Text a spreadsheet would read as a formula (starting with =, +, -, @,
    /// a tab or a return) gets a leading apostrophe: a client's notes
    /// mustn't run as a formula when the file is opened.
    static func neutralized(_ text: String) -> String {
        guard let first = text.first, "=+-@\t\r".contains(first) else { return text }
        return "'" + text
    }

    /// Quoted when it holds a comma, a quote or a line break; quotes doubled.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func money(_ amount: Double) -> Cell {
        .plain(String(format: "%.2f", InvoiceLines.roundedToCent(amount)))
    }

    static func day(_ date: Date?, calendar: Calendar = .current) -> Cell {
        guard let date else { return .plain("") }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return .plain(String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
    }

    // MARK: - The files

    static func clients(_ clients: [Client], operatorID: String) -> String {
        let rows = clients.filter { $0.operatorID == operatorID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { client -> [Cell] in
                [.text(client.name), .text(client.phone), .text(client.email), .text(client.address),
                 .plain(client.isActive ? "Active" : "Inactive"), .text(client.tags.joined(separator: "; ")),
                 .plain(client.isComped ? "Yes" : "No"), .plain(client.taxExempt ? "Yes" : "No"),
                 .plain(String(format: "%.0f", client.defaultDiscountPercent)),
                 .plain("\(client.totalVisits)"), day(client.lastServiceDate), day(client.createdAt), .text(client.notes)]
            }
        return document(header: ["Name", "Phone", "Email", "Address", "Status", "Tags", "No Charge",
                                 "Tax Exempt", "Discount %", "Route Visits", "Last Service", "Added", "Notes"], rows: rows)
    }

    static func invoices(_ documents: [Proposal], operatorID: String) -> String {
        let rows = documents.filter { $0.operatorID == operatorID && $0.isInvoice }
            .sorted { $0.createdAt < $1.createdAt }
            .map { invoice -> [Cell] in
                [.text(invoice.invoiceNumber), .text(invoice.clientName), .plain(invoice.invoiceStatus.rawValue),
                 day(invoice.createdAt), day(invoice.invoiceSentAt), day(invoice.invoiceDueDate), day(invoice.invoicePaidAt),
                 money(invoice.subtotal), money(invoice.appliedDiscount),
                 .plain(Proposal.percentText(invoice.taxRate)), money(invoice.taxAmount),
                 money(invoice.total), money(invoice.amountPaid), money(invoice.balanceDue), .text(invoice.revisionOf)]
            }
        return document(header: ["Invoice", "Client", "Status", "Created", "Sent", "Due", "Paid",
                                 "Subtotal", "Discount", "Tax Rate %", "Tax", "Total", "Amount Paid", "Balance Due",
                                 "Revision Of"],
                        rows: rows)
    }

    /// The invoices whose lines are income: billed and not void
    /// (`InvoiceRecords.isBilled`), and a void one that still holds money
    /// (Void keeps a paid invoice's money and work with it, and Payments
    /// lists that money). A draft isn't billed yet, and a revised invoice's
    /// lines and money went to its revision, so counting either would add
    /// income early or twice. Invoices lists them all.
    static func billedInvoices(_ documents: [Proposal], operatorID: String) -> [Proposal] {
        documents.filter { invoice in
            invoice.operatorID == operatorID && invoice.isInvoice
                && (InvoiceRecords.isBilled(invoice)
                    || (invoice.voidedAt != nil && invoice.paymentsTotal > Payments.tolerance))
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// Every line of every billed invoice (`billedInvoices`), in invoice
    /// order: what a bookkeeper needs to split income by service. A line's
    /// total is before the invoice's discount and tax, which are in Invoices.
    static func invoiceLines(_ documents: [Proposal], operatorID: String) -> String {
        let rows = billedInvoices(documents, operatorID: operatorID).flatMap { invoice in
            invoice.sortedLineItems.map { line -> [Cell] in
                [.text(invoice.invoiceNumber), .text(invoice.clientName), .plain(invoice.invoiceStatus.rawValue),
                 day(invoice.createdAt), .text(line.serviceName), .text(line.zoneLabel),
                 .plain(DecimalText.trimmed(line.quantity)), .text(line.unitType == "perSqFt" ? "sq ft" : "each"),
                 .plain(unitPrice(of: line)), money(line.lineTotal)]
            }
        }
        return document(header: ["Invoice", "Client", "Status", "Created", "Service", "Place", "Quantity", "Unit",
                                 "Unit Price", "Line Total"], rows: rows)
    }

    /// What one unit was charged, worked out from the line's total: the
    /// stored unit price goes stale when an amount is typed or edited (the
    /// PDF never prints it). A square-foot rate keeps up to six decimals
    /// ($0.035, or $0.03998 from a typed $1,999 over 50,000 sq ft), so
    /// quantity × this is the line total to within rounding; Line Total is
    /// the figure charged.
    static func unitPrice(of line: ProposalLineItem) -> String {
        if line.unitType == "perSqFt", line.quantity > 0, line.quantity.isFinite {
            return DecimalText.trimmed(line.lineTotal / line.quantity, places: 6)
        }
        return String(format: "%.2f", InvoiceLines.roundedToCent(line.lineTotal))
    }

    /// Every amount received, oldest first: what the business's books need
    /// to match deposits. The same money the reports count
    /// (`Payments.receiptEntries`): each payment, and the rest of an invoice
    /// marked paid without a payment for it, on the day it was marked paid.
    /// Those used to be left out, so this file added up to less than Money In.
    static func payments(_ documents: [Proposal], operatorID: String) -> String {
        let rows = Payments.receiptEntries(documents.filter { $0.operatorID == operatorID })
            .sorted { $0.date < $1.date }
            .map { receipt -> [Cell] in
                [day(receipt.date), .text(receipt.invoice.invoiceNumber), .text(receipt.invoice.clientName),
                 money(receipt.amount),
                 .text(method(of: receipt)),
                 .text(receipt.payment?.note ?? "Marked paid with no payment recorded")]
            }
        return document(header: ["Received", "Invoice", "Client", "Amount", "Method", "Note"], rows: rows)
    }

    /// "Marked Paid" for money an invoice was marked paid with, whether it's
    /// still on that invoice or a revision took it as a payment
    /// (InvoiceRecords.recordImpliedPayment: no method, "Marked paid on …").
    static func method(of receipt: Payments.Receipt) -> String {
        guard let payment = receipt.payment else { return "Marked Paid" }
        if payment.method.isEmpty, payment.note.hasPrefix(InvoiceRecords.impliedPaymentNotePrefix) { return "Marked Paid" }
        return payment.method
    }

    /// Every job in the Service Log, oldest first, one row per job.
    static func serviceHistory(_ records: [ServiceRecord], operatorID: String, in context: ModelContext) -> String {
        let invoices = (try? context.fetch(FetchDescriptor<Proposal>())) ?? []
        let numbers = Dictionary(invoices.filter(\.isInvoice).map { ($0.id.uuidString, $0.invoiceNumber) },
                                 uniquingKeysWith: { first, _ in first })
        let contracts = Contracts.all(in: context)
        let rows = records.filter { $0.operatorID == operatorID }
            .sorted { $0.performedAt < $1.performedAt }
            .map { record -> [Cell] in
                let number = numbers[record.invoiceID]
                let status: String = switch ServiceLog.billingStatus(
                    of: record, invoiced: number != nil, covered: ServiceLog.isCovered(record, contracts: contracts)) {
                case .invoiced: "Invoiced"
                case .notTracked: "Billing Not Tracked"
                case .noCharge: "No Charge"
                case .covered: "Covered by Contract"
                case .notBilled: "Not Billed"
                }
                let source: String = switch record.source {
                case .route: "Route"
                case .visit: "Scheduled Visit"
                case .manual: "Logged by Hand"
                case .beforeLog: "Before the Service History"
                }
                return [day(record.performedAt), .text(record.clientName), .text(record.propertyAddress),
                        .plain(source), .text(record.routeName),
                        .text(record.lines.map(\.name).joined(separator: "; ")),
                        .plain(record.minutes >= 1 ? "\(Int(record.minutes.rounded()))" : ""),
                        money(ServiceLog.total(of: record)),
                        money(InvoiceLines.roundedToCent(ServiceLog.charge(of: record, contracts: contracts)
                            .reduce(0) { $0 + $1.price })),
                        .plain(status), .text(number ?? ""), .text(record.notes)]
            }
        // Total is what the work came to; Charged, what it bills (under a
        // contract: its price, or nothing for work it covers).
        return document(header: ["Date", "Client", "Address", "Recorded From", "Route", "Services", "Minutes",
                                 "Total", "Charged", "Billing", "Invoice", "Notes"], rows: rows)
    }

    /// Every proposal (not yet an invoice), oldest first: what was quoted.
    static func proposals(_ documents: [Proposal], operatorID: String) -> String {
        let rows = documents.filter { $0.operatorID == operatorID && !$0.isInvoice }
            .sorted { $0.createdAt < $1.createdAt }
            .map { proposal -> [Cell] in
                [day(proposal.createdAt), .text(proposal.clientName), .text(proposal.clientAddress),
                 .text(proposal.sortedLineItems.map(\.serviceName).joined(separator: "; ")),
                 money(proposal.subtotal), money(proposal.appliedDiscount), money(proposal.taxAmount),
                 money(proposal.total), day(proposal.validUntil), .text(proposal.notes)]
            }
        return document(header: ["Created", "Client", "Address", "Services", "Subtotal", "Discount", "Tax", "Total",
                                 "Valid Until", "Notes"], rows: rows)
    }

    /// Every scheduled visit, by date: the Schedule, past and ahead.
    static func schedule(_ visits: [ScheduledVisit], operatorID: String, catalog: [ServiceItem]) -> String {
        let names = Dictionary(catalog.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = visits.filter { $0.operatorID == operatorID }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .map { visit -> [Cell] in
                [day(visit.scheduledDate), .text(visit.clientName), .text(visit.clientAddress),
                 .plain(visit.status.rawValue), .text(visit.visitReason),
                 .text(visit.expectedServiceIDs.compactMap { names[$0] }.joined(separator: "; ")),
                 .plain(visit.isRecurring ? "Yes" : "No"), .text(visit.notes)]
            }
        return document(header: ["Date", "Client", "Address", "Status", "Reason", "Services", "Repeats", "Notes"],
                        rows: rows)
    }

    /// Every contract, oldest first: what was agreed, and where it stands.
    static func contracts(_ contracts: [Contract], operatorID: String, catalog: [ServiceItem],
                          now: Date = .now) -> String {
        let names = Dictionary(catalog.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = contracts.filter { $0.operatorID == operatorID }
            .sorted { $0.startDate < $1.startDate }
            .map { contract -> [Cell] in
                [.text(contract.name), .text(contract.clientName), .plain(Contracts.status(of: contract, now: now).title),
                 day(contract.startDate), day(contract.endDate), .plain(Contracts.pricing(of: contract).title),
                 money(contract.price), .plain(Contracts.pricing(of: contract) == .season ? "\(contract.installments)" : ""),
                 .text(contract.serviceIDs.compactMap { names[$0] }.joined(separator: "; ")),
                 .text(ContractSchedule.hasSchedule(contract) ? ContractSchedule.summary(of: contract) : ""),
                 day(contract.signedAt), day(contract.cancelledAt), .text(contract.notes)]
            }
        return document(header: ["Contract", "Client", "Status", "Starts", "Ends", "Pricing", "Price", "Payments",
                                 "Services", "Visits", "Signed", "Cancelled", "Notes"], rows: rows)
    }

    /// `contents` written to a temporary file named for PlowR, `kind` and the
    /// day ("PlowR Clients 2026-09-30.csv"), to share. Delete Account & Data
    /// removes these (AccountEraser).
    static func file(_ kind: String, contents: String, now: Date = .now,
                     directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard case .plain(let stamp) = day(now) else { throw CocoaError(.fileWriteUnknown) }
        let url = directory.appending(path: "PlowR \(kind) \(stamp).csv")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }
}
