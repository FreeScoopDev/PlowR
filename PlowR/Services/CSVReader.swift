import Foundation

/// Reads a spreadsheet saved as CSV, for Import Clients: from Excel, Numbers,
/// Google Sheets, another app's export, or PlowR's own (CSVExport). No
/// third-party code, so what it handles is written and tested here:
/// - **Text encoding:** UTF-8 (with or without a byte-order mark), UTF-16
///   with a byte-order mark (Excel's "Unicode Text"), and otherwise Windows
///   Latin-1, which Excel on Windows writes and which reads any bytes.
/// - **Separator:** comma, semicolon (Excel where a comma is the decimal
///   mark) or tab, whichever the first line has most of, outside quotes.
/// - **Quotes (RFC 4180):** a quoted field can hold separators, line breaks
///   and doubled quotes ("" for ").
/// - **Line endings:** CRLF, LF or CR.
/// - **Tidying:** spaces around a field are trimmed, blank rows dropped, short
///   rows padded to the header's width, and the apostrophe a spreadsheet (or
///   CSVExport) puts before text that looks like a formula is taken off.
nonisolated enum CSVReader {
    struct Table: Equatable {
        /// The first row: column names.
        var header: [String]
        /// The rows after it, each as wide as the header (or wider, if a row
        /// had extra cells).
        var rows: [[String]]
    }

    enum Problem: Error, Equatable {
        /// Nothing but blank lines.
        case empty
        /// Not text: a spreadsheet saved in its own format (.xlsx, .numbers).
        case notText
    }

    /// The table in `data`: the first row is the header.
    static func read(_ data: Data) throws -> Table {
        guard let text = decode(data) else { throw Problem.notText }
        let rows = parse(text, separator: separator(of: text))
        guard let header = rows.first else { throw Problem.empty }
        let width = header.count
        let body = rows.dropFirst().map { row in row.count < width ? row + Array(repeating: "", count: width - row.count) : row }
        return Table(header: header, rows: Array(body))
    }

    // MARK: - Text

    /// The file as text, or nil if it isn't text (a zipped .xlsx or .numbers,
    /// which start "PK", or anything with NUL bytes outside UTF-16).
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        if bytes.starts(with: [0x50, 0x4B]) || data.contains(0) { return nil }    // "PK": a zip
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    /// Comma, semicolon or tab: whichever the first line holds most of,
    /// outside quotes. A comma when there's a tie or none.
    static func separator(of text: String) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle() }
            if !inQuotes, character.isNewline { break }
            if !inQuotes, counts[character] != nil { counts[character, default: 0] += 1 }
        }
        let best = counts.max { a, b in a.value < b.value || (a.value == b.value && a.key != ",") }
        return (best?.value ?? 0) > 0 ? best?.key ?? "," : ","
    }

    // MARK: - Fields

    /// Every row's fields, RFC 4180, blank rows dropped.
    static func parse(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var wasQuoted = false
        /// Just past a closing quote: spaces before the separator aren't the field's.
        var afterQuote = false
        var characters = Array(text)[...]
        func endField() {
            row.append(tidy(field, quoted: wasQuoted))
            field = ""
            wasQuoted = false
            afterQuote = false
        }
        func endRow() {
            endField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }
        while let character = characters.popFirst() {
            if inQuotes {
                if character == "\"" {
                    if characters.first == "\"" {
                        field.append("\"")
                        characters.removeFirst()
                    } else {
                        inQuotes = false
                        afterQuote = true
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.allSatisfy(\.isWhitespace) {
                // A quote opens a field only at its start (spaces aside).
                field = ""
                inQuotes = true
                wasQuoted = true
            } else if character == separator {
                endField()
            } else if afterQuote && !character.isNewline && character.isWhitespace {
                continue
            } else if character.isNewline {
                // "\r\n" is one Character in Swift; a lone "\r" or "\n" too.
                endRow()
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty || wasQuoted { endRow() }
        return rows
    }

    /// A field as kept: trimmed (an unquoted one; a quoted one keeps what's
    /// inside its quotes but loses spaces outside them), and without the
    /// apostrophe that guards text a spreadsheet would read as a formula.
    static func tidy(_ field: String, quoted: Bool) -> String {
        let trimmed = quoted ? field.trimmingCharacters(in: .newlines) : field.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("'"), let second = trimmed.dropFirst().first, "=+-@\t\r".contains(second) {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
