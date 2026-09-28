import Foundation
import SwiftData

/// Invoice numbers: INV-0001, INV-0002, … one sequence per operator, and
/// revisions of an invoice as INV-0042-R1, INV-0042-R2, …
///
/// The next number is one past the highest number already used. A revision
/// holds its original's number, so INV-0007-R1 keeps 7 taken even if INV-0007
/// itself is deleted. The next number used to be the count of invoices plus one,
/// copied into four screens: delete INV-0003 of five and the next invoice was
/// numbered INV-0005, a number a live invoice already had. Revisions were
/// counted the same way.
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

    /// One past the highest invoice number in `used`, counting each revision as
    /// its original's number.
    static func next(after used: [String]) -> String {
        let highest = used.compactMap { sequence(of: base(of: $0)) }.max() ?? 0
        return String(format: "%@%04d", prefix, highest + 1)
    }

    /// As `next(after:)`, but when the numbers in use couldn't be read (nil, a
    /// store error) it gives a number that can't collide with the sequence,
    /// INV-yyyyMMdd-HHmmss, instead of starting again at INV-0001.
    static func next(after used: [String]?, now: Date) -> String {
        guard let used else { return prefix + timestamp(now) }
        return next(after: used)
    }

    /// `number` if nothing in `used` has it, otherwise the next free number.
    /// For a number chosen earlier (for a preview) and saved later.
    static func confirmed(_ number: String, used: [String]?, now: Date) -> String {
        guard let used, used.contains(number) else { return number }
        return next(after: used, now: now)
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
    /// "INV-0042-R1" when -R1 and -R3 exist gives "INV-0042-R4". If `used`
    /// couldn't be read (nil), a timestamp suffix that can't collide.
    static func nextRevision(of number: String, used: [String]?, now: Date = Date()) -> String {
        let marker = base(of: number) + "-R"
        guard let used else { return marker + timestamp(now) }
        let highest = used.compactMap { candidate -> Int? in
            guard candidate.hasPrefix(marker) else { return nil }
            let digits = candidate.dropFirst(marker.count)
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(digits)
        }.max() ?? 0
        return "\(marker)\(highest + 1)"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    // MARK: - Reading the store

    /// Every invoice number this operator has used, including revisions, read
    /// from the store at the moment it's needed (unsaved changes included).
    /// nil if the store couldn't be read.
    @MainActor
    static func usedNumbers(operatorID: String, in context: ModelContext) -> [String]? {
        let descriptor = FetchDescriptor<Proposal>(
            predicate: #Predicate { $0.operatorID == operatorID && $0.invoiceNumber != "" }
        )
        return (try? context.fetch(descriptor))?.map(\.invoiceNumber)
    }

    @MainActor
    static func next(operatorID: String, in context: ModelContext) -> String {
        next(after: usedNumbers(operatorID: operatorID, in: context), now: Date())
    }

    @MainActor
    static func confirmed(_ number: String, operatorID: String, in context: ModelContext) -> String {
        confirmed(number, used: usedNumbers(operatorID: operatorID, in: context), now: Date())
    }

    @MainActor
    static func nextRevision(of number: String, operatorID: String, in context: ModelContext) -> String {
        nextRevision(of: number, used: usedNumbers(operatorID: operatorID, in: context))
    }
}
