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
            case .tags: ["tags", "tag", "labels", "label", "groups", "group"]
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
            (.state, ["state", "province"]),
            (.firstName, ["first name"]),
            (.lastName, ["last name"]),
            (.company, ["company", "organization"]),
            (.address, ["address"]),
            (.notes, ["note", "notes", "comment", "comments"])
        ]
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

    /// The field a header names: exactly, else by a word in it.
    static func field(for header: String) -> Field {
        let name = normalized(header)
        if let exact = Field.allCases.first(where: { $0.headers.contains(name) }) { return exact }
        let words = " \(name) "
        return Field.keywords.first { _, keys in keys.contains { words.contains(" \($0) ") } }?.0 ?? .ignore
    }

    /// Each column's field, guessed from the header. A field goes to the first
    /// column that names it (a second phone isn't imported); notes may come
    /// from several. A service address wins over a billing one: it's where
    /// the work is. Beside City, State, ZIP or Apt columns, an "Address"
    /// column is the street, so those columns aren't lost.
    static func guess(_ header: [String]) -> [Field] {
        let names = header.map(normalized)
        var fields = header.map(field(for:))
        let addressFields: Set<Field> = [.address, .street, .street2, .city, .state, .zip]
        let hasServiceAddress = names.indices.contains {
            names[$0].hasPrefix("service ") && addressFields.contains(fields[$0])
        }
        if hasServiceAddress {
            for index in names.indices where names[index].hasPrefix("billing ") { fields[index] = .ignore }
        }
        let hasParts = fields.contains { [.street2, .city, .state, .zip].contains($0) }
        if hasParts, !fields.contains(.street), let address = fields.firstIndex(of: .address) {
            fields[address] = .street
        }
        var taken = Set<Field>()
        return fields.map { field in
            guard field != .ignore, field != .notes else { return field }
            return taken.insert(field).inserted ? field : .ignore
        }
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
        // A full address, with any Apt, City, State or ZIP column it doesn't
        // already hold; or the address from its parts.
        let full = value(.address).split(whereSeparator: \.isNewline).joined(separator: ", ")
        let held = " \(normalized(full)) "
        let stateZip = [value(.state), value(.zip)].filter { !$0.isEmpty }.joined(separator: " ")
        let parts = [full.isEmpty ? value(.street) : "", value(.street2), value(.city), stateZip]
            .filter { !$0.isEmpty && !held.contains(" \(normalized($0)) ") }
        draft.address = ([full] + parts).filter { !$0.isEmpty }.joined(separator: ", ")
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
        let cut = lower.range(of: "ext") ?? lower.range(of: "x")
        var digits = (cut.map { lower[..<$0.lowerBound] } ?? lower[...]).filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
        return digits.count >= 7 ? digits : nil
    }

    /// Street words in their short form, so "12 Main Street" and "12 Main St."
    /// are the same address.
    private static let shortWords = [
        "street": "st", "avenue": "ave", "av": "ave", "road": "rd", "drive": "dr", "lane": "ln", "court": "ct",
        "boulevard": "blvd", "place": "pl", "terrace": "ter", "circle": "cir", "parkway": "pkwy", "highway": "hwy",
        "route": "rte", "north": "n", "south": "s", "east": "e", "west": "w", "apartment": "apt", "suite": "ste",
        "usa": ""
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
    /// phone with another name is a new client, noted. Rows match each other
    /// too, so a client listed twice is added once. Row numbers count the
    /// header as row 1, as a spreadsheet shows them.
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
                outcomes.append(.problem(row: index + 2, reason: "No name"))
                continue
            }
            let name = normalized(draft.name), address = addressKey(draft.address)
            let samePhone = phoneKey(draft.phone).flatMap { byPhone[$0] } ?? []
            if !address.isEmpty, let match = byNameAddress[name + "|" + address] {
                outcomes.append(.duplicate(draft, of: match.name))
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
