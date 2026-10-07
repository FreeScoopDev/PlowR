import Foundation

/// Import Clients: from a spreadsheet's table (CSVReader) to the clients it
/// would add. Matching columns to client fields (guessed from the headers,
/// changeable), building each row's client, and sorting rows into new, a
/// client PlowR already has, another property of one, or a row with a problem.
/// Pure, and indexed so thousands of rows take a moment: the screens and
/// saving use it.
nonisolated enum ClientImport {
    /// What a column holds.
    enum Field: String, CaseIterable, Identifiable {
        case ignore, name, firstName, lastName, company, phone, email
        case address, street, street2, city, state, zip, notes, tags

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ignore: "Don't Import"
            case .name: "Name"
            case .firstName: "First Name"
            case .lastName: "Last Name"
            case .company: "Company"
            case .phone: "Phone"
            case .email: "Email"
            case .address: "Full Address"
            case .street: "Street"
            case .street2: "Apt / Unit"
            case .city: "City"
            case .state: "State"
            case .zip: "ZIP"
            case .notes: "Notes"
            case .tags: "Tags"
            }
        }

        /// Header names that mean this field exactly, as other apps and
        /// people write them (compared `normalized`).
        var headers: [String] {
            switch self {
            case .ignore: []
            case .name: ["name", "client", "client name", "customer", "customer name", "full name", "display name",
                         "contact", "contact name"]
            case .firstName: ["first name", "first", "given name", "firstname"]
            case .lastName: ["last name", "last", "surname", "family name", "lastname"]
            case .company: ["company", "company name", "business", "business name", "organization",
                            "organization name"]
            case .phone: ["phone", "phone number", "mobile", "mobile phone", "cell", "cell phone", "telephone", "tel",
                          "primary phone", "home phone", "work phone", "business phone", "phone 1"]
            case .email: ["email", "e mail", "email address", "e mail address", "primary email"]
            case .address: ["address", "full address", "service address", "property address", "location",
                            "billing address", "address 1 formatted"]
            case .street: ["street", "street address", "address 1", "address line 1", "street 1", "service street 1",
                           "service street", "billing street 1", "billing street", "home street", "business street"]
            case .street2: ["address 2", "address line 2", "street 2", "unit", "apt", "apartment", "suite",
                            "service street 2", "billing street 2"]
            case .city: ["city", "town", "service city", "billing city", "home city", "business city"]
            case .state: ["state", "province", "region", "service state", "billing state", "home state",
                          "business state"]
            case .zip: ["zip", "zip code", "postal code", "postcode", "zip postal code", "service zip",
                        "service zip code", "billing zip", "billing zip code", "service postal code",
                        "home postal code", "business postal code"]
            case .notes: ["notes", "note", "comments", "comment", "description"]
            case .tags: ["tags", "tag", "labels", "label", "groups", "group", "group membership"]
            }
        }

        /// Words that mean a field inside a longer header ("Client Phone #",
        /// "Customer Email Address"), tried when no header matches exactly.
        /// The first field with one of its words in the header wins.
        static let keywords: [(Field, [String])] = [
            (.email, ["email", "e mail"]),
            (.phone, ["phone", "mobile", "cell"]),
            (.zip, ["zip", "postal"]),
            (.street2, ["address 2", "line 2", "street 2"]),
            (.street, ["street"]),
            (.city, ["city"]),
            (.state, ["state", "province", "region"]),
            (.firstName, ["first name"]),
            (.lastName, ["last name"]),
            (.company, ["company", "organization"]),
            (.address, ["address"]),
            (.notes, ["note", "notes", "comment", "comments"])
        ]

        /// Words that make a header about a field, not the field itself:
        /// Google's "Phone 1 - Label" before "Phone 1 - Value", "Email Opt In",
        /// "Address Country". Never matched by a keyword.
        static let notTheField = ["type", "label", "opt", "status", "country", "verified", "date", "id"]
    }

    /// Text as compared: lowercased, punctuation as spaces, letters apart
    /// from digits ("Address1" is "address 1"), spaces single.
    static func normalized(_ text: String) -> String {
        var out = ""
        var last: Character = " "
        for character in text.lowercased() {
            let kept: Character = character.isLetter || character.isNumber ? character : " "
            if kept != " ", last != " ", kept.isNumber != last.isNumber { out.append(" ") }
            if kept != " " || last != " " { out.append(kept) }
            last = kept
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The field a header names exactly, if it does.
    static func exactField(for header: String) -> Field? {
        let name = normalized(header)
        return Field.allCases.first { $0.headers.contains(name) }
    }

    /// The field a header names by a word in it ("Client Phone #"), unless
    /// it's about the field rather than the field ("Phone Type").
    static func keywordField(for header: String) -> Field? {
        let words = " \(normalized(header)) "
        guard !Field.notTheField.contains(where: { words.contains(" \($0) ") }) else { return nil }
        return Field.keywords.first { _, keys in keys.contains { words.contains(" \($0) ") } }?.0
    }

    /// The field a header names: exactly, else by a word in it.
    static func field(for header: String) -> Field {
        exactField(for: header) ?? keywordField(for: header) ?? .ignore
    }

    /// Each column's field, guessed from the header, and from `rows` when
    /// given. Each field goes to one column (a second phone isn't imported);
    /// notes may come from several. Headers that name a field exactly claim
    /// it before those that only have its word, so Google's "Phone 1 - Value"
    /// isn't beaten by a column beside it. Among columns that name a field
    /// alike, the one with the most filled in wins (Outlook's empty Business
    /// columns before the Home ones), then the first. A service address wins
    /// over a billing one: it's where the work is. Beside City, State, ZIP or
    /// Apt columns, a bare "Address" column is the street.
    static func guess(_ header: [String], rows: [[String]] = []) -> [Field] {
        let names = header.map(normalized)
        var exact = header.map(exactField(for:))
        var byWord = header.map(keywordField(for:))
        let addressFields: Set<Field> = [.address, .street, .street2, .city, .state, .zip]
        let hasServiceAddress = names.indices.contains {
            names[$0].hasPrefix("service ") && addressFields.contains(exact[$0] ?? byWord[$0] ?? .ignore)
        }
        if hasServiceAddress {
            for index in names.indices where names[index].hasPrefix("billing ") {
                exact[index] = nil
                byWord[index] = nil
            }
        }
        let parts: [Field] = [.street2, .city, .state, .zip]
        let hasParts = names.indices.contains { parts.contains(exact[$0] ?? byWord[$0] ?? .ignore) }
        let hasStreet = names.indices.contains { (exact[$0] ?? byWord[$0]) == .street }
        if hasParts, !hasStreet,
           let bare = names.indices.first(where: { ["address", "location"].contains(names[$0]) }) {
            exact[bare] = .street
        }
        let filled = header.indices.map { column in
            rows.reduce(0) { $0 + (column < $1.count && !$1[column].isEmpty ? 1 : 0) }
        }
        var fields = Array(repeating: Field.ignore, count: header.count)
        for candidates in [exact, byWord] {
            let claimed = Set(fields)
            let wanted = Dictionary(grouping: header.indices.filter { candidates[$0] != nil && fields[$0] == .ignore },
                                    by: { candidates[$0] ?? .ignore })
            for (field, columns) in wanted where !claimed.contains(field) || field == .notes {
                if field == .notes {
                    columns.forEach { fields[$0] = .notes }
                } else if let best = columns.max(by: { (filled[$0], -$0) < (filled[$1], -$1) }) {
                    fields[best] = field
                }
            }
        }
        return fields
    }

    /// A client as a row gives it.
    struct Draft: Equatable {
        var name = ""
        var phone = ""
        var email = ""
        var address = ""
        var notes = ""
        var tags: [String] = []
    }

    /// The client in `row`, with `fields` saying what each column holds.
    static func draft(from row: [String], fields: [Field]) -> Draft {
        func value(_ field: Field) -> String {
            guard let index = fields.firstIndex(of: field), row.indices.contains(index) else { return "" }
            return row[index]
        }
        var draft = Draft()
        let first = value(.firstName), last = value(.lastName), company = value(.company)
        let person = value(.name).isEmpty ? [first, last].filter { !$0.isEmpty }.joined(separator: " ") : value(.name)
        draft.name = person.isEmpty ? company : person
        draft.phone = value(.phone)
        draft.email = value(.email)
        // The full address (or the street), with any Apt, City, State or ZIP
        // column it doesn't already hold after its street ("12 Claremont Rd"
        // still needs Claremont).
        let full = value(.address).split(whereSeparator: \.isNewline).joined(separator: ", ")
        let base = full.isEmpty ? value(.street) : full
        let held = " \(normalized(String(base.drop { $0 != "," }))) "
        func lacking(_ part: String) -> Bool { !part.isEmpty && !held.contains(" \(normalized(part)) ") }
        // State and ZIP side by side, as written: "NH 03743".
        let stateZip = [value(.state), value(.zip)].filter(lacking).joined(separator: " ")
        let parts = [value(.street2), value(.city)].filter(lacking) + [stateZip]
        draft.address = ([base] + parts).filter { !$0.isEmpty }.joined(separator: ", ")
        var notes = fields.indices.filter { fields[$0] == .notes && row.indices.contains($0) && !row[$0].isEmpty }
            .map { row[$0] }
        // A company beside a person's name is kept, in the notes.
        if !person.isEmpty, !company.isEmpty, normalized(company) != normalized(person) {
            notes.insert("Company: \(company)", at: 0)
        }
        draft.notes = notes.joined(separator: "\n")
        // Separated by ; or , or Google Contacts' " ::: ". Google's own
        // "* myContacts" isn't one of the business's tags.
        draft.tags = value(.tags).replacingOccurrences(of: ":::", with: ";")
            .split { $0 == ";" || $0 == "," }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        return draft
    }

    // MARK: - Matching clients PlowR has

    /// A phone number as compared: its digits, without an extension ("x12",
    /// "ext. 12") or the leading 1 of an 11-digit number. Too few digits to
    /// be a phone number: nil.
    static func phoneKey(_ phone: String) -> String? {
        let lower = phone.lowercased()
        // An extension ends the number: "x" or "ext" then digits, after a
        // whole number ("Fax 603…" and "Box 12, 603…" aren't extensions).
        var digits = lower.filter(\.isNumber)
        if let ext = lower.range(of: #"(ext\.?|x)\s*\d{1,6}\s*$"#, options: .regularExpression) {
            let before = lower[..<ext.lowerBound].filter(\.isNumber)
            if before.count >= 7 { digits = before }
        }
        if digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
        return digits.count >= 7 ? digits : nil
    }

    /// Street words in their short form, so "12 Main Street" and "12 Main St."
    /// are the same address.
    private static let shortWords = [
        "street": "st", "avenue": "ave", "av": "ave", "road": "rd", "drive": "dr", "lane": "ln", "court": "ct",
        "boulevard": "blvd", "place": "pl", "terrace": "ter", "circle": "cir", "parkway": "pkwy", "highway": "hwy",
        "route": "rte", "north": "n", "south": "s", "east": "e", "west": "w", "apartment": "apt", "suite": "ste",
        "usa": "", "us": ""
    ]

    /// An address as compared: `normalized`, street words short, no country.
    static func addressKey(_ address: String) -> String {
        let text = normalized(address).replacingOccurrences(of: "united states", with: "")
        return text.split(separator: " ").map { shortWords[String($0)] ?? String($0) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A client PlowR already has, or one earlier in the file, as matched.
    /// A client with properties is one Known per property address, all with
    /// the client's ID, so a row at any of their places matches them.
    struct Known: Equatable {
        /// A client's ID (uuidString), or `row:N` for one earlier in the file.
        var id: String
        var name: String
        var phone: String
        var address: String
    }

    /// What a row would do.
    enum Outcome: Equatable {
        /// Added as a new client. `sharesPhoneWith`: a client with the same
        /// phone and another name (a household, or an office line for several
        /// places), named in the preview so the user can check.
        case new(Draft, sharesPhoneWith: String?)
        /// The same as a client PlowR has, or one earlier in the file: skipped.
        case duplicate(Draft, of: String)
        /// The same client at another address, kept as one of their
        /// properties (only when the user asks: `addressesAsProperties`).
        /// `ofID`: the Known's ID, a client or a row added before it.
        case property(Draft, of: String, ofID: String)
        /// Not imported, and why.
        case problem(row: Int, reason: String)
    }

    struct Preview: Equatable {
        var outcomes: [Outcome]
        var new: [Draft] { outcomes.compactMap { if case let .new(draft, _) = $0 { draft } else { nil } } }
        var duplicates: Int { outcomes.filter { if case .duplicate = $0 { true } else { false } }.count }
        var properties: Int { outcomes.filter { if case .property = $0 { true } else { false } }.count }
        /// New clients whose phone another client has.
        var sharedPhones: Int { outcomes.filter { if case .new(_, .some) = $0 { true } else { false } }.count }
        var problems: [(row: Int, reason: String)] {
            outcomes.compactMap { if case let .problem(row, reason) = $0 { (row, reason) } else { nil } }
        }

        static func == (a: Preview, b: Preview) -> Bool { a.outcomes == b.outcomes }
    }

    /// What importing `table` would do, one outcome per row. A row is a
    /// duplicate when a known client has its name and phone, or its name and
    /// address (an empty address matches nothing). With
    /// `addressesAsProperties`, the same name and phone at an address the
    /// client doesn't have is their property instead; a client with no
    /// address isn't given one (duplicates are skipped, not merged). The same
    /// phone at the same address is a duplicate whatever the name; with
    /// another name at another address it's a new client, noted (a
    /// household's second place, or an office line). Rows match each other
    /// too, so a client listed twice is added once. Row numbers are the
    /// spreadsheet's (`Table.rowNumber`).
    static func preview(_ table: CSVReader.Table, fields: [Field], existing: [Known],
                        addressesAsProperties: Bool = false) -> Preview {
        // Indexed by phone and by name and address: each row is a lookup,
        // not a pass over every client.
        var byPhone: [String: [(name: String, known: Known)]] = [:]
        var byNameAddress: [String: Known] = [:]
        var addresses: [String: Set<String>] = [:]      // a Known ID's address keys
        func add(_ known: Known) {
            let name = normalized(known.name), address = addressKey(known.address)
            if let phone = phoneKey(known.phone) { byPhone[phone, default: []].append((name, known)) }
            if !address.isEmpty, byNameAddress[name + "|" + address] == nil { byNameAddress[name + "|" + address] = known }
            addresses[known.id, default: []].insert(address)
        }
        existing.forEach(add)
        var outcomes: [Outcome] = []
        outcomes.reserveCapacity(table.rows.count)
        for (index, row) in table.rows.enumerated() {
            let draft = draft(from: row, fields: fields)
            guard !draft.name.isEmpty else {
                outcomes.append(.problem(row: table.rowNumber(index), reason: "No name"))
                continue
            }
            let name = normalized(draft.name), address = addressKey(draft.address)
            let samePhone = phoneKey(draft.phone).flatMap { byPhone[$0] } ?? []
            if !address.isEmpty, let match = byNameAddress[name + "|" + address] {
                outcomes.append(.duplicate(draft, of: match.name))
            } else if !address.isEmpty,
                      let sameDoor = samePhone.first(where: { addresses[$0.known.id]?.contains(address) == true }) {
                // The same phone at the same place is the same client under
                // another name ("Pat & Kim Doe" for "Pat Doe").
                outcomes.append(.duplicate(draft, of: sameDoor.known.name))
            } else if let owner = samePhone.first(where: { $0.name == name })?.known {
                let theirs = addresses[owner.id] ?? []
                if addressesAsProperties, !address.isEmpty, !theirs.contains(address), !theirs.contains("") {
                    outcomes.append(.property(draft, of: owner.name, ofID: owner.id))
                    add(Known(id: owner.id, name: owner.name, phone: draft.phone, address: draft.address))
                } else {
                    outcomes.append(.duplicate(draft, of: owner.name))
                }
            } else {
                outcomes.append(.new(draft, sharesPhoneWith: samePhone.first?.known.name))
                add(Known(id: "row:\(index)", name: draft.name, phone: draft.phone, address: draft.address))
            }
        }
        return Preview(outcomes: outcomes)
    }
}
