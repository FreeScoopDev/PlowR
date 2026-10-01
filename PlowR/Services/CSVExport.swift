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
        let lines = [header.map { escape($0) }] + rows.map { $0.map(render) }
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
                 .plain(client.isComped ? "Yes" : "No"), .plain(String(format: "%.0f", client.defaultDiscountPercent)),
                 .plain("\(client.totalVisits)"), day(client.lastServiceDate), day(client.createdAt), .text(client.notes)]
            }
        return document(header: ["Name", "Phone", "Email", "Address", "Status", "Tags", "No Charge",
                                 "Discount %", "Route Visits", "Last Service", "Added", "Notes"], rows: rows)
    }

    static func invoices(_ documents: [Proposal], operatorID: String) -> String {
        let rows = documents.filter { $0.operatorID == operatorID && $0.isInvoice }
            .sorted { $0.createdAt < $1.createdAt }
            .map { invoice -> [Cell] in
                [.text(invoice.invoiceNumber), .text(invoice.clientName), .plain(invoice.invoiceStatus.rawValue),
                 day(invoice.createdAt), day(invoice.invoiceSentAt), day(invoice.invoiceDueDate), day(invoice.invoicePaidAt),
                 money(invoice.subtotal), money(invoice.appliedDiscount), money(invoice.taxAmount),
                 money(invoice.total), money(invoice.amountPaid), money(invoice.balanceDue), .text(invoice.revisionOf)]
            }
        return document(header: ["Invoice", "Client", "Status", "Created", "Sent", "Due", "Paid",
                                 "Subtotal", "Discount", "Tax", "Total", "Amount Paid", "Balance Due", "Revision Of"],
                        rows: rows)
    }

    /// Every payment received, oldest first: what the business's books need
    /// to match deposits. An invoice marked paid before payments were kept
    /// has none, and shows as paid in Invoices.
    static func payments(_ documents: [Proposal], operatorID: String) -> String {
        let rows = documents.filter { $0.operatorID == operatorID && $0.isInvoice }
            .flatMap { invoice in invoice.sortedPayments.map { (invoice, $0) } }
            .sorted { $0.1.receivedAt < $1.1.receivedAt }
            .map { invoice, payment -> [Cell] in
                [day(payment.receivedAt), .text(invoice.invoiceNumber), .text(invoice.clientName),
                 money(payment.amount), .text(payment.method), .text(payment.note)]
            }
        return document(header: ["Received", "Invoice", "Client", "Amount", "Method", "Note"], rows: rows)
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
