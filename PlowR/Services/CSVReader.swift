import Foundation

/// Reads a spreadsheet saved as CSV, for Import Clients: from Excel, Numbers,
/// Google Sheets, another app's export, or PlowR's own (CSVExport). No
/// third-party code, so what it handles is written and tested here:
/// - **Text encoding:** UTF-8 (with or without a byte-order mark), UTF-16
///   with a byte-order mark (Excel's "Unicode Text"), and otherwise Windows
///   Latin-1 (Excel on Windows), read byte by byte so a text file always
///   reads: the five bytes it leaves undefined become "�", visible in the
///   preview, rather than the whole file being refused or read wrong.
/// - **Separator:** comma, semicolon (Excel where a comma is the decimal
///   mark) or tab, whichever the header line has most of outside quotes
///   (blank lines before it skipped; ties go comma, semicolon, tab), or as
///   Excel's "sep=;" first line says.
/// - **Quotes (RFC 4180):** a quote at a field's start opens a quoted field,
///   which can hold separators, line breaks and doubled quotes ("" for ").
///   A quote anywhere else (O"Brien, 5'6") is just a character.
/// - **Line endings:** CRLF, LF or CR, and only those: a vertical tab
///   (FileMaker's in-field return) stays in the field.
/// - **Tidying, for an import:** spaces and line breaks around a field are
///   trimmed (inside quotes too), blank rows dropped, short rows padded to
///   the header's width, and the apostrophe a spreadsheet (or CSVExport) puts
///   before text that looks like a formula is taken off.
/// - **An unclosed quote** takes the rest of the file into one field, as a
///   spreadsheet would; the line it opened on is reported, so the import can
///   say so.
nonisolated enum CSVReader {
    struct Table: Equatable {
        /// The first row: column names.
        var header: [String]
        /// The rows after it, each as wide as the header (or wider, if a row
        /// had extra cells).
        var rows: [[String]]
        /// The file line where a quote opened and never closed, if one did.
        var unclosedQuoteLine: Int?
        /// Each row's number as a spreadsheet shows it (blank rows count, a
        /// line break inside quotes doesn't, and Excel's "sep=" line isn't
        /// shown), so a problem can name its row. Empty for a table not read
        /// from a file.
        var rowNumbers: [Int] = []

        /// The spreadsheet row of `rows[index]`; without `rowNumbers`, the
        /// header is row 1.
        func rowNumber(_ index: Int) -> Int {
            rowNumbers.indices.contains(index) ? rowNumbers[index] : index + 2
        }
    }

    enum Problem: Error, Equatable {
        /// Nothing but blank lines.
        case empty
        /// Not text: a spreadsheet saved in its own format (.xlsx, .numbers,
        /// an old .xls).
        case notText
    }

    /// The table in `data`: the first row is the header.
    static func read(_ data: Data) throws -> Table {
        guard let text = decode(data) else { throw Problem.notText }
        let (hint, body, linesBefore) = separatorHint(in: text)
        let parsed = parse(body, separator: hint ?? separator(of: body), firstLine: linesBefore + 1)
        // Before the header, a line of only separators and quotes is blank,
        // whichever separator the file uses (as `separator(of:)` treats it).
        let leading = parsed.rows.prefix { row in row.joined().allSatisfy { ",;\t\" ".contains($0) } }
        let all = Array(parsed.rows.dropFirst(leading.count))
        guard let header = all.first else { throw Problem.empty }
        let width = header.count
        let rows = all.dropFirst().map { row in
            row.count < width ? row + Array(repeating: "", count: width - row.count) : row
        }
        return Table(header: header, rows: Array(rows), unclosedQuoteLine: parsed.unclosedQuoteLine,
                     rowNumbers: Array(parsed.numbers.dropFirst(leading.count + 1)))
    }

    // MARK: - Text

    /// The file as text, or nil if it isn't text (a zipped .xlsx or .numbers,
    /// which start "PK", or anything else with NUL bytes, like an old .xls).
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            let rest = data.dropFirst(3)
            return String(data: rest, encoding: .utf8) ?? windows1252(rest)
        }
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        if bytes.starts(with: [0x50, 0x4B]) || data.contains(0) { return nil }    // "PK": a zip
        return String(data: data, encoding: .utf8) ?? windows1252(data)
    }

    /// Windows Latin-1, byte by byte: what Excel on Windows writes. Foundation
    /// refuses a file with one of the five bytes it leaves undefined, and
    /// ISO Latin-1 would turn its smart quotes, dashes and € into invisible
    /// control characters; here those five become "�" and the rest read.
    static func windows1252(_ data: some Collection<UInt8>) -> String {
        let high: [UInt32] = [0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
                              0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
                              0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
                              0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178]
        var text = String.UnicodeScalarView()
        for byte in data {
            let value = (0x80...0x9F).contains(byte) ? high[Int(byte) - 0x80] : UInt32(byte)
            text.append(Unicode.Scalar(value) ?? "\u{FFFD}")
        }
        return String(text)
    }

    /// A line ending: CR, LF or CRLF (one Character in Swift).
    static func isLineEnd(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }

    /// Excel's "sep=;" first line, the text after it, and how many lines it
    /// took (so line numbers stay the file's). No hint: nil, the whole text, 0.
    static func separatorHint(in text: String) -> (Character?, Substring, Int) {
        let firstLine = text.prefix { !isLineEnd($0) }
        // Spaces only: "sep=" + a tab is a hint too.
        let trimmed = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: " ")).lowercased()
        guard trimmed.hasPrefix("sep="), trimmed.count == 5, let separator = trimmed.last else {
            return (nil, text[...], 0)
        }
        // The hint's line and its one line ending: blank lines after it count.
        var rest = text.dropFirst(firstLine.count)
        if let end = rest.first, isLineEnd(end) { rest = rest.dropFirst() }
        return (separator, rest, 1)
    }

    /// Comma, semicolon or tab: whichever the header line (the first with
    /// anything on it) holds most of, outside quotes. Ties, and none, go to
    /// the first of comma, semicolon, tab.
    static func separator(of text: some StringProtocol) -> Character {
        let order: [Character] = [",", ";", "\t"]
        var counts: [Character: Int] = [:]
        var inQuotes = false
        var lineHasContent = false
        for character in text {
            if character == "\"" { inQuotes.toggle() }
            if !inQuotes, isLineEnd(character) {
                if lineHasContent { break }
                counts = [:]        // a blank line's separators aren't the header's
                continue
            }
            // A line of only separators and quotes (",,," or "") is blank, as
            // parse() treats it.
            if !character.isWhitespace, !order.contains(character), character != "\"" { lineHasContent = true }
            if !inQuotes, order.contains(character) { counts[character, default: 0] += 1 }
        }
        var best: Character = ","
        for candidate in order where counts[candidate, default: 0] > counts[best, default: 0] { best = candidate }
        return best
    }

    // MARK: - Fields

    /// Every row's fields, RFC 4180, blank rows dropped; each kept row's
    /// number counting the blank ones (`numbers`, from 1); and the line an
    /// unclosed quote opened on, if any.
    static func parse(_ text: some StringProtocol, separator: Character,
                      firstLine: Int = 1) -> (rows: [[String]], unclosedQuoteLine: Int?, numbers: [Int]) {
        var rows: [[String]] = []
        var numbers: [Int] = []
        var record = 0
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var wasQuoted = false
        /// Spaces after a closing quote: dropped before a separator or a line
        /// end, kept if more text follows ("Smith" Lawn Co).
        var afterQuote = false
        var heldSpaces = ""
        var line = firstLine
        var quoteLine = 0
        func endField() {
            row.append(tidy(field, quoted: wasQuoted))
            field = ""
            wasQuoted = false
            afterQuote = false
            heldSpaces = ""
        }
        func endRow() {
            endField()
            record += 1
            if row.contains(where: { !$0.isEmpty }) {
                rows.append(row)
                numbers.append(record)
            }
            row = []
        }
        for character in text {
            if inQuotes {
                if isLineEnd(character) { line += 1 }
                if character == "\"" {
                    inQuotes = false
                    afterQuote = true
                } else {
                    field.append(character)
                }
                continue
            }
            if character == "\"" && afterQuote && heldSpaces.isEmpty {
                // "" inside a quoted field: a quote, and still quoted.
                field.append("\"")
                inQuotes = true
                afterQuote = false
            } else if character == "\"" && !wasQuoted && field.allSatisfy(\.isWhitespace) {
                // A quote opens a field only at its start (spaces aside).
                field = ""
                inQuotes = true
                wasQuoted = true
                quoteLine = line
            } else if character == separator {
                endField()
            } else if isLineEnd(character) {
                endRow()
                line += 1
            } else if afterQuote && character.isWhitespace {
                heldSpaces.append(character)
            } else {
                if afterQuote {
                    field += heldSpaces
                    heldSpaces = ""
                    afterQuote = false
                }
                field.append(character)
            }
        }
        let unclosed = inQuotes ? quoteLine : nil
        if !field.isEmpty || !row.isEmpty || wasQuoted { endRow() }
        return (rows, unclosed, numbers)
    }

    /// A field as kept: trimmed of spaces and line breaks (quoted or not),
    /// and without the apostrophe that guards text a spreadsheet would read
    /// as a formula.
    static func tidy(_ field: String, quoted: Bool) -> String {
        let trimmed = field.trimmingCharacters(in: quoted ? .whitespacesAndNewlines : .whitespaces)
        if trimmed.hasPrefix("'"), let second = trimmed.dropFirst().first, "=+-@\t\r".contains(second) {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
