import Foundation

/// The rules for the expenses Home's Expenses logs: reading a typed amount,
/// the total every screen and file uses, what to suggest for "What", and the
/// months a list is grouped by.
enum Expenses {
    /// The amount typed, to the cent, or nil when it can't be saved:
    /// unreadable (as InvoiceLines.isUnreadable reads it, so a decimal comma
    /// works where the region writes one), zero or less, or beyond any real
    /// amount. A refund isn't an expense.
    static func amount(typed text: String, locale: Locale = .current) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !InvoiceLines.isUnreadable(text, locale: locale),
              let value = DecimalText.number(text, locale: locale),
              value < InvoiceLines.maxAmount else { return nil }
        let cents = InvoiceLines.roundedToCent(value)
        return cents > 0 ? cents : nil
    }

    /// A typed quantity: nil when it can't be read; 0 for none. Kept to the
    /// places the editor and the Expenses file show (`DecimalText.trimmed`'s
    /// four), so reopening a saved expense reads back what was stored and
    /// isn't counted as a change.
    static func quantity(typed text: String, locale: Locale = .current) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 0 }
        guard let value = DecimalText.number(text, locale: locale), value >= 0 else { return nil }
        return (value * 10_000).rounded() / 10_000
    }

    /// What `expenses` add up to, to the cent: the one sum the list, the
    /// Expenses file's line and the summary use, so they always agree.
    static func total(_ expenses: [Expense]) -> Double {
        InvoiceLines.roundedToCent(expenses.reduce(0) { $0 + InvoiceLines.roundedToCent($1.amount) })
    }

    /// Earlier items this business typed that start with `prefix` (any case),
    /// most recent first, each once whatever its case (its latest spelling),
    /// leaving out the one already typed. Only the business's own: PlowR has
    /// no list of materials of its own.
    static func itemSuggestions(_ expenses: [Expense], operatorID: String, prefix: String) -> [String] {
        let typed = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen: Set<String> = [typed]
        return expenses.filter { $0.operatorID == operatorID }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
            .compactMap { expense -> String? in
                let item = expense.item.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = item.lowercased()
                guard !item.isEmpty, key.hasPrefix(typed), seen.insert(key).inserted else { return nil }
                return item
            }
    }

    /// `items` by the month of `date`, newest month first, newest first in
    /// each month (then the later made).
    static func byMonth<Item>(_ items: [Item], date: (Item) -> Date, made: (Item) -> Date,
                              calendar: Calendar = .current) -> [(month: Date, items: [Item])] {
        let sorted = items.sorted { (date($0), made($0)) > (date($1), made($1)) }
        var groups: [(month: Date, items: [Item])] = []
        for item in sorted {
            let month = calendar.dateInterval(of: .month, for: date(item))?.start ?? date(item)
            if let last = groups.indices.last, groups[last].month == month {
                groups[last].items.append(item)
            } else {
                groups.append((month, [item]))
            }
        }
        return groups
    }

    /// A month's heading: "November 2026".
    static func monthTitle(_ month: Date) -> String {
        month.formatted(.dateTime.month(.wide).year())
    }

    /// What an expense is called on its row and in its delete question: what
    /// was bought, or its category.
    static func name(of expense: Expense) -> String {
        let item = expense.item.trimmingCharacters(in: .whitespacesAndNewlines)
        return item.isEmpty ? expense.category.title : item
    }

    /// The delete question, naming the expense and its amount.
    static func deleteTitle(for expense: Expense) -> String {
        "Delete \u{201C}\(name(of: expense))\u{201D}, \(Money.text(expense.amount))?"
    }
}
