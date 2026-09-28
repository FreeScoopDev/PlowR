import Foundation
import SwiftData

/// Invoice numbers: INV-0001, INV-0002, … one sequence per operator, and
/// revisions of an invoice as INV-0042-R1, INV-0042-R2, …
///
/// The next number is one past the highest number already used. It used to be
/// the count of invoices plus one, copied into four screens: delete INV-0003 of
/// five and the next invoice was numbered INV-0005, a number a live invoice
/// already had. Revisions were counted the same way.
///
/// `nonisolated`: the numbering itself is plain string work, used from views and
/// tests. Only the helpers that read the store are main-actor.
nonisolated enum InvoiceNumbering {
    static let prefix = "INV-"

    /// 42 for "INV-0042"; nil for a revision ("INV-0042-R1") or anything else.
    static func sequence(of number: String) -> Int? {
        guard number.hasPrefix(prefix) else { return nil }
        let digits = number.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    /// One past the highest invoice number in `used`.
    static func next(after used: [String]) -> String {
        let highest = used.compactMap(sequence(of:)).max() ?? 0
        return String(format: "%@%04d", prefix, highest + 1)
    }

    /// The invoice a number belongs to, without any revision suffix:
    /// "INV-0042-R2" → "INV-0042". Older copies of copies ("INV-0042-R1-R1")
    /// resolve to the same base.
    static func base(of number: String) -> String {
        var result = number
        while let range = result.range(of: #"-R\d+$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }

    /// The next revision of the invoice `number` belongs to: one past the
    /// highest revision of its base in `used`. Revising "INV-0042" or
    /// "INV-0042-R1" when -R1 and -R3 exist gives "INV-0042-R4".
    static func nextRevision(of number: String, used: [String]) -> String {
        let root = base(of: number)
        let marker = root + "-R"
        let highest = used.compactMap { candidate -> Int? in
            guard candidate.hasPrefix(marker) else { return nil }
            let digits = candidate.dropFirst(marker.count)
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(digits)
        }.max() ?? 0
        return "\(marker)\(highest + 1)"
    }

    // MARK: - Reading the store

    /// Every invoice number this operator has used, including revisions, read
    /// from the store at the moment it's needed (unsaved changes included).
    @MainActor
    static func usedNumbers(operatorID: String, in context: ModelContext) -> [String] {
        let all = (try? context.fetch(FetchDescriptor<Proposal>())) ?? []
        return all.filter { $0.operatorID == operatorID && !$0.invoiceNumber.isEmpty }.map(\.invoiceNumber)
    }

    @MainActor
    static func next(operatorID: String, in context: ModelContext) -> String {
        next(after: usedNumbers(operatorID: operatorID, in: context))
    }

    @MainActor
    static func nextRevision(of number: String, operatorID: String, in context: ModelContext) -> String {
        nextRevision(of: number, used: usedNumbers(operatorID: operatorID, in: context))
    }
}
