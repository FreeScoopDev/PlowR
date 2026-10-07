import Foundation

/// Import Clients: from a spreadsheet's table (CSVReader) to the clients it
/// would add. Matching columns to client fields (guessed from the headers,
/// changeable), building each row's client, and sorting rows into new, a
/// client PlowR already has, another property of one, or a row with a problem.
/// Pure: the screens and saving (ClientImport+Saving) use it.
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

        /// Header names that mean this field, as other apps and people write
        /// them (compared lowercased, punctuation as spaces).
        var headers: [String] {
            switch self {
            case .ignore: []
            case .name: ["name", "client", "client name", "customer", "customer name", "full name", "display name",
                         "contact", "contact name"]
            case .firstName: ["first name", "first", "given name", "firstname"]
            case .lastName: ["last name", "last", "surname", "family name", "lastname"]
            case .company: ["company", "company name", "business", "business name", "organization"]
            case .phone: ["phone", "phone number", "mobile", "mobile phone", "cell", "cell phone", "telephone", "tel",
                          "primary phone", "home phone", "work phone", "phone 1"]
            case .email: ["email", "e mail", "email address", "e mail address", "primary email"]
            case .address: ["address", "full address", "service address", "property address", "location",
                            "billing address", "street address full"]
            case .street: ["street", "street address", "address 1", "address line 1", "street 1", "service street 1",
                           "service street", "billing street 1", "billing street"]
            case .street2: ["address 2", "address line 2", "street 2", "unit", "apt", "apartment", "suite",
                            "service street 2", "billing street 2"]
            case .city: ["city", "town", "service city", "billing city"]
            case .state: ["state", "province", "region", "service state", "billing state"]
            case .zip: ["zip", "zip code", "postal code", "postcode", "service zip", "service zip code", "billing zip",
                        "billing zip code", "service postal code"]
            case .notes: ["notes", "note", "comments", "comment", "description"]
            case .tags: ["tags", "tag", "labels", "label", "groups", "group"]
            }
        }
    }

    /// A header as compared: lowercased, punctuation as spaces, spaces single.
    static func normalized(_ text: String) -> String {
        let spaced = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    /// Each column's field, guessed from the header. A field goes to the first
    /// column that names it (a second "Phone" isn't imported); notes may come
    /// from several. A service address wins over a billing one: it's where
    /// the work is.
    static func guess(_ header: [String]) -> [Field] {
        var taken = Set<Field>()
        var fields: [Field] = []
        let names = header.map(normalized)
        let hasService = names.contains { $0.hasPrefix("service ") }
        for name in names {
            let isBilling = name.hasPrefix("billing ")
            let match = Field.allCases.first { $0.headers.contains(name) && !(hasService && isBilling) } ?? .ignore
            if match != .ignore, match != .notes, taken.contains(match) {
                fields.append(.ignore)
            } else {
                fields.append(match)
                taken.insert(match)
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
        let first = value(.firstName), last = value(.lastName)
        let person = value(.name).isEmpty ? [first, last].filter { !$0.isEmpty }.joined(separator: " ") : value(.name)
        draft.name = person.isEmpty ? value(.company) : person
        draft.phone = value(.phone)
        draft.email = value(.email)
        if !value(.address).isEmpty {
            draft.address = value(.address).replacingOccurrences(of: "\n", with: ", ")
        } else {
            let street = [value(.street), value(.street2)].filter { !$0.isEmpty }.joined(separator: ", ")
            let stateZip = [value(.state), value(.zip)].filter { !$0.isEmpty }.joined(separator: " ")
            draft.address = [street, value(.city), stateZip].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        var notes = fields.indices.filter { fields[$0] == .notes && row.indices.contains($0) && !row[$0].isEmpty }
            .map { row[$0] }
        // A company beside a person's name is kept, in the notes.
        if !person.isEmpty, !value(.company).isEmpty { notes.insert("Company: \(value(.company))", at: 0) }
        draft.notes = notes.joined(separator: "\n")
        draft.tags = value(.tags).split { $0 == ";" || $0 == "," }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return draft
    }

    // MARK: - Matching clients PlowR has

    /// A phone number as compared: its digits, without a leading 1 on an
    /// 11-digit number. Too few digits to be a phone number: nil.
    static func phoneKey(_ phone: String) -> String? {
        var digits = phone.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") { digits.removeFirst() }
        return digits.count >= 7 ? digits : nil
    }

    /// A client PlowR already has (or one earlier in the file), as matched.
    struct Known: Equatable {
        /// A client's ID (uuidString), or `row:N` for one earlier in the file.
        var id: String
        var name: String
        var phone: String
        var address: String
    }

    /// What a row would do.
    enum Outcome: Equatable {
        /// Added as a new client.
        case new(Draft)
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
        var new: [Draft] { outcomes.compactMap { if case .new(let d) = $0 { d } else { nil } } }
        var duplicates: Int { outcomes.filter { if case .duplicate = $0 { true } else { false } }.count }
        var properties: Int { outcomes.filter { if case .property = $0 { true } else { false } }.count }
        var problems: [(row: Int, reason: String)] {
            outcomes.compactMap { if case let .problem(row, reason) = $0 { (row, reason) } else { nil } }
        }

        static func == (a: Preview, b: Preview) -> Bool { a.outcomes == b.outcomes }
    }

    /// What importing `table` would do. A row is a duplicate when its phone
    /// matches a known client's, or its name and address both do; with
    /// `addressesAsProperties`, the same name and phone at another address is
    /// that client's property instead. Rows are matched against each other
    /// too, so a client listed twice is added once. Row numbers count the
    /// header as row 1, as a spreadsheet shows them.
    static func preview(_ table: CSVReader.Table, fields: [Field], existing: [Known],
                        addressesAsProperties: Bool = false) -> Preview {
        var known = existing
        var outcomes: [Outcome] = []
        for (index, row) in table.rows.enumerated() {
            let draft = draft(from: row, fields: fields)
            guard !draft.name.isEmpty else {
                outcomes.append(.problem(row: index + 2, reason: "No name"))
                continue
            }
            let matches = known.filter { isSame(draft, $0) }
            if let first = matches.first {
                // An address already known (listed twice, or already theirs) is
                // a duplicate; only a new one can be another property.
                let addressKnown = matches.contains { normalized($0.address) == normalized(draft.address) }
                if addressesAsProperties, !addressKnown,
                   let owner = matches.first(where: { isSamePersonElsewhere(draft, $0) }) {
                    outcomes.append(.property(draft, of: owner.name, ofID: owner.id))
                    known.append(Known(id: owner.id, name: draft.name, phone: draft.phone, address: draft.address))
                } else {
                    outcomes.append(.duplicate(draft, of: first.name))
                }
                continue
            }
            outcomes.append(.new(draft))
            known.append(Known(id: "row:\(index)", name: draft.name, phone: draft.phone, address: draft.address))
        }
        return Preview(outcomes: outcomes)
    }

    /// The same client: the same phone, or the same name and address.
    static func isSame(_ draft: Draft, _ known: Known) -> Bool {
        if let phone = phoneKey(draft.phone), phone == phoneKey(known.phone) { return true }
        return normalized(draft.name) == normalized(known.name)
            && normalized(draft.address) == normalized(known.address)
    }

    /// The same name and phone, at an address that isn't theirs yet.
    static func isSamePersonElsewhere(_ draft: Draft, _ known: Known) -> Bool {
        guard let phone = phoneKey(draft.phone), phone == phoneKey(known.phone),
              normalized(draft.name) == normalized(known.name), !draft.address.isEmpty else { return false }
        return normalized(draft.address) != normalized(known.address)
    }
}
