import Foundation

/// How the Documents list is ordered, chosen in its filter menu and kept.
enum DocumentSort: String, CaseIterable {
    /// The list's own order: newest made first, paid ones by when they were paid.
    case newest = "Newest"
    /// Soonest due first; nothing due (a proposal, an invoice without a date) last.
    case dueDate = "Due Date"
    /// Largest total first.
    case amount = "Amount"
    /// By client name, A to Z.
    case client = "Client"

    /// Where the choice is kept (standard preferences, which Delete
    /// Account & Data clears).
    static let storageKey = "documentSort"
}

/// Search and sort for the Documents list, outside the view so each rule
/// is tested.
enum DocumentList {
    /// What a document is sorted by, read once per document: a total adds
    /// up its lines.
    struct Key {
        var createdAt: Date
        var due: Date?
        var amount: Double
        var clientName: String
        var id: UUID
    }

    static func key(_ document: Proposal) -> Key {
        // Only an invoice is due; the row shows a date as due only on one.
        Key(createdAt: document.createdAt,
            due: document.isInvoice ? document.invoiceDueDate : nil,
            amount: document.total,
            clientName: document.clientName,
            id: document.id)
    }

    /// Whether `typed` finds a document: every word in its client's name,
    /// its invoice number or its notes, by the clients' search rule
    /// (`ClientSearch`). No search finds every document.
    static func matches(_ typed: String, clientName: String, number: String, notes: String) -> Bool {
        ClientSearch.matches(typed, in: [clientName, number, notes])
    }

    static func matches(_ document: Proposal, query typed: String) -> Bool {
        matches(typed, clientName: document.clientName, number: document.invoiceNumber, notes: document.notes)
    }

    /// The documents in `sort`'s order. Newest keeps the order given (the
    /// list's own, unchanged since before there was a choice).
    static func sorted(_ documents: [Proposal], by sort: DocumentSort) -> [Proposal] {
        guard sort != .newest else { return documents }
        return ordered(documents, by: sort) { key($0) }
    }

    /// `items` in `sort`'s order. Ties go newest first, then by ID, so the
    /// order never shuffles between looks.
    static func ordered<T>(_ items: [T], by sort: DocumentSort, key: (T) -> Key) -> [T] {
        let keyed = items.map { (item: $0, key: key($0)) }
        return keyed.sorted { inOrder($0.key, $1.key, by: sort) }.map(\.item)
    }

    /// Whether `a` comes before `b`.
    static func inOrder(_ a: Key, _ b: Key, by sort: DocumentSort) -> Bool {
        switch sort {
        case .newest:
            break
        case .dueDate:
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
        case .amount:
            if a.amount != b.amount { return a.amount > b.amount }
        case .client:
            // Capitals and accents don't order names (no forced ordering,
            // as localizedStandardCompare has): equal names tie.
            let order = a.clientName.compare(b.clientName,
                                             options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                                             locale: .current)
            if order != .orderedSame { return order == .orderedAscending }
        }
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}
