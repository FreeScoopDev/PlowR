import Foundation

/// How a typed search finds a client: one rule for the Clients list and
/// every client picker (a new document's Select Client, Add Visit, Add
/// Stops), so they all find the same clients the same way.
///
/// A client is found when every word typed is somewhere in their name,
/// address, phone or a tag, whatever the capitals or accents ("jose" finds
/// José). The spaces around the text don't count (the keyboard adds one
/// after a word it suggests), and only spaces is no search. A word of
/// digits also finds a phone written with dashes or brackets: "5550142"
/// finds "555-0142".
enum ClientSearch {
    /// What a typed search looks for: the text without the spaces around it.
    static func query(_ typed: String) -> String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words of a search, folded for comparing. Empty: no search.
    static func words(_ typed: String) -> [String] {
        fold(query(typed)).split(whereSeparator: \.isWhitespace).map { String($0) }
    }

    /// Text as a search compares it: no capitals, no accents.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// How two names order, A to Z: capitals and accents don't order them
    /// (no forced order, as `localizedStandardCompare` has), so equal names
    /// tie; numbers go by value. One order for the Documents list's Client
    /// sort and Home's Search.
    static func nameOrder(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: .current)
    }

    /// Whether every word of `typed` is in one of `fields`. No search finds
    /// everything. The rule shared with the Documents search.
    static func matches(_ typed: String, in fields: [String], phone: String = "") -> Bool {
        let words = words(typed)
        if words.isEmpty { return true }
        let folded = (fields + [phone]).map { fold($0) }
        let phoneDigits = digits(phone)
        return words.allSatisfy { word in
            folded.contains { $0.contains(word) } || phoneMatches(word, phoneDigits: phoneDigits)
        }
    }

    /// Whether a client with these details is found by `typed`. `also`
    /// adds fields to look in (a place's name and address, on Add Stops).
    static func matches(_ typed: String, name: String, address: String, phone: String,
                        tags: [String], also: [String] = []) -> Bool {
        matches(typed, in: [name, address] + tags + also, phone: phone)
    }

    static func matches(_ client: Client, query typed: String, also: [String] = []) -> Bool {
        matches(typed, name: client.name, address: client.address, phone: client.phone,
                tags: client.tags, also: also)
    }

    /// The clients `typed` finds, in the order given.
    static func filter(_ clients: [Client], query typed: String) -> [Client] {
        guard !words(typed).isEmpty else { return clients }
        return clients.filter { matches($0, query: typed) }
    }

    // MARK: - Phone digits

    private static let phonePunctuation = Set("()-+./")

    private static func digits(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber })
    }

    /// A word written like a phone number (digits, maybe with dashes or
    /// brackets) is looked for among the phone's digits alone.
    private static func phoneMatches(_ word: String, phoneDigits: String) -> Bool {
        let wordDigits = digits(word)
        guard !wordDigits.isEmpty, !phoneDigits.isEmpty,
              word.allSatisfy({ ($0.isASCII && $0.isNumber) || phonePunctuation.contains($0) })
        else { return false }
        return phoneDigits.contains(wordDigits)
    }
}
