import Foundation
import Testing
@testable import PlowR

/// Import Clients: columns guessed from headers, each row's client, and what
/// the import would do with each row.
struct ClientImportTests {
    typealias F = ClientImport.Field

    private func table(_ header: [String], _ rows: [[String]]) -> CSVReader.Table {
        CSVReader.Table(header: header, rows: rows)
    }

    @Test func headersAsAppsAndPeopleWriteThem() {
        #expect(ClientImport.guess(["Client Name", "Mobile Phone", "E-mail", "Notes"]) == [.name, .phone, .email, .notes])
        #expect(ClientImport.guess(["First Name", "Last Name", "Street Address", "City", "State", "Zip Code"])
            == [.firstName, .lastName, .street, .city, .state, .zip])
        #expect(ClientImport.guess(["Something Else", "PHONE NUMBER"]) == [.ignore, .phone])
    }

    @Test func aSecondColumnForAFieldIsntTakenButNotesAre() {
        #expect(ClientImport.guess(["Name", "Phone", "Work Phone", "Notes", "Comments"])
            == [.name, .phone, .ignore, .notes, .notes])
    }

    // Jobber-style exports list a billing and a service address: the work is
    // at the service one.
    @Test func theServiceAddressWinsOverBilling() {
        let fields = ClientImport.guess(["Name", "Billing Street 1", "Billing City", "Service Street 1", "Service City"])
        #expect(fields == [.name, .ignore, .ignore, .street, .city])
    }

    @Test func aClientFromItsColumns() {
        let fields: [F] = [.firstName, .lastName, .company, .phone, .street, .street2, .city, .state, .zip, .tags, .notes]
        let row = ["Pat", "Doe", "Doe Farms", "603-555-0100", "1 Main St", "Unit 2", "Claremont", "NH", "03743",
                   "commercial; priority", "Gate 1234"]
        let draft = ClientImport.draft(from: row, fields: fields)
        #expect(draft.name == "Pat Doe")
        #expect(draft.phone == "603-555-0100")
        #expect(draft.address == "1 Main St, Unit 2, Claremont, NH 03743")
        #expect(draft.tags == ["commercial", "priority"])
        #expect(draft.notes == "Company: Doe Farms\nGate 1234")
    }

    @Test func aCompanyWithNoPersonIsTheName() {
        let draft = ClientImport.draft(from: ["Acme Lots", "1 Mill Rd\nDock 4"], fields: [.company, .address])
        #expect(draft.name == "Acme Lots")
        #expect(draft.notes.isEmpty)
        #expect(draft.address == "1 Mill Rd, Dock 4")
    }

    @Test func phoneNumbersMatchByTheirDigits() {
        #expect(ClientImport.phoneKey("(603) 555-0100") == "6035550100")
        #expect(ClientImport.phoneKey("+1 603.555.0100") == "6035550100")
        #expect(ClientImport.phoneKey("ext 12") == nil)
    }

    @Test func thePreviewSortsRows() {
        let t = table(["Name", "Phone", "Address"], [
            ["Pat Doe", "603-555-0100", "1 Main St"],          // already in PlowR, by name and phone
            ["Sam Roe", "", "2 Elm St"],                      // new
            ["", "603-555-0199", "3 Oak St"],                 // no name
            ["sam  roe", "", "2 elm st."],                    // the same as the row above
            ["Lee Poe", "(603) 555-0177", "4 Pine St"],       // new
        ])
        let existing = [ClientImport.Known(id: "c1", name: "Pat Doe", phone: "6035550100", address: "")]
        let preview = ClientImport.preview(t, fields: [.name, .phone, .address], existing: existing)
        #expect(preview.new.map(\.name) == ["Sam Roe", "Lee Poe"])
        #expect(preview.duplicates == 2)
        #expect(preview.problems.map(\.row) == [4])           // spreadsheet row: the header is row 1
        #expect(preview.outcomes.first == .duplicate(ClientImport.draft(from: t.rows[0], fields: [.name, .phone, .address]),
                                                     of: "Pat Doe"))
    }

    // One row per property: only when asked, and to the right client.
    @Test func anotherAddressBecomesAPropertyOnlyWhenAsked() {
        let t = table(["Name", "Phone", "Address"], [
            ["Pat Doe", "603-555-0100", "1 Main St"],
            ["Pat Doe", "603-555-0100", "9 Lake Rd"],
            ["Pat Doe", "603-555-0100", "9 Lake Rd"],         // listed twice
        ])
        let off = ClientImport.preview(t, fields: [.name, .phone, .address], existing: [])
        #expect(off.new.count == 1 && off.duplicates == 2 && off.properties == 0)
        let on = ClientImport.preview(t, fields: [.name, .phone, .address], existing: [], addressesAsProperties: true)
        #expect(on.new.count == 1 && on.properties == 1 && on.duplicates == 1)
        if case let .property(_, of, ofID) = on.outcomes[1] {
            #expect(of == "Pat Doe" && ofID == "row:0")
        } else {
            Issue.record("Expected a property")
        }
        // A different name with the same phone isn't the same person's property.
        let other = table(["Name", "Phone", "Address"], [["Pat Doe", "603-555-0100", "1 Main St"],
                                                         ["Kim Doe", "603-555-0100", "9 Lake Rd"]])
        let household = ClientImport.preview(other, fields: [.name, .phone, .address], existing: [],
                                             addressesAsProperties: true)
        #expect(household.new.map(\.name) == ["Pat Doe", "Kim Doe"] && household.properties == 0)
    }

    // A household or an office line: the same phone, another name. A new
    // client, said in the preview, not skipped as a duplicate.
    @Test func aSharedPhoneWithAnotherNameIsANewClientNoted() {
        let t = table(["Name", "Phone"], [["Kim Doe", "(603) 555-0100"], ["Pat Doe", "603 555 0100"]])
        let existing = [ClientImport.Known(id: "c1", name: "Patricia Doe", phone: "6035550100", address: "1 Main St")]
        let preview = ClientImport.preview(t, fields: [.name, .phone], existing: existing)
        #expect(preview.new.count == 2 && preview.duplicates == 0 && preview.sharedPhones == 2)
        #expect(preview.outcomes[0] == .new(ClientImport.Draft(name: "Kim Doe", phone: "(603) 555-0100"),
                                            sharesPhoneWith: "Patricia Doe"))
    }

    @Test func theSameNameAtAnEmptyAddressIsNotAMatch() {
        let t = table(["Name", "Phone", "Address"], [["Sam Roe", "", ""], ["Sam Roe", "", ""]])
        let existing = [ClientImport.Known(id: "c1", name: "Sam Roe", phone: "", address: "")]
        // Two people can share a name; with no phone or address to tell, each is added.
        #expect(ClientImport.preview(t, fields: [.name, .phone, .address], existing: existing).new.count == 2)
    }

    @Test func streetWordsAndCaseDontMakeAnotherAddress() {
        #expect(ClientImport.addressKey("12 North Main Street, Claremont, NH, United States")
            == ClientImport.addressKey("12 n main st claremont nh"))
        #expect(ClientImport.addressKey("4 Oak Avenue") == ClientImport.addressKey("4 OAK AVE."))
        #expect(ClientImport.addressKey("4 Oak Avenue") != ClientImport.addressKey("4 Oak Court"))
        let t = table(["Name", "Address"], [["Lee Poe", "4 Oak Avenue"]])
        let existing = [ClientImport.Known(id: "c1", name: "lee poe", phone: "", address: "4 Oak Ave.")]
        #expect(ClientImport.preview(t, fields: [.name, .address], existing: existing).duplicates == 1)
    }

    @Test func phoneExtensionsAndShortNumbers() {
        #expect(ClientImport.phoneKey("603-555-0100 x12") == "6035550100")
        #expect(ClientImport.phoneKey("603-555-0100 ext. 12") == "6035550100")
        #expect(ClientImport.phoneKey("555-0100") == "5550100")      // seven digits: a number
        #expect(ClientImport.phoneKey("55-0100") == nil)             // six: not
        #expect(ClientImport.phoneKey("") == nil)
    }

    // An existing client with another property: a row at either place is them.
    @Test func aRowAtAnExistingClientsPropertyIsADuplicate() {
        let id = UUID().uuidString
        let existing = [ClientImport.Known(id: id, name: "Pat Doe", phone: "6035550100", address: "1 Main St"),
                        ClientImport.Known(id: id, name: "Pat Doe", phone: "6035550100", address: "9 Lake Rd")]
        let t = table(["Name", "Phone", "Address"], [
            ["Pat Doe", "603-555-0100", "9 Lake Road"],
            ["Pat Doe", "603-555-0100", "3 Hill St"],
        ])
        let preview = ClientImport.preview(t, fields: [.name, .phone, .address], existing: existing,
                                           addressesAsProperties: true)
        #expect(preview.duplicates == 1)
        #expect(preview.outcomes[1] == .property(ClientImport.draft(from: t.rows[1], fields: [.name, .phone, .address]),
                                                 of: "Pat Doe", ofID: id))
    }

    // Three places for one client in the file: one client, two properties.
    @Test func aChainOfAddressesAllGoToTheFirstRow() {
        let t = table(["Name", "Phone", "Address"], [
            ["Pat Doe", "603-555-0100", "1 Main St"],
            ["Pat Doe", "603-555-0100", "9 Lake Rd"],
            ["PAT DOE", "6035550100", "3 Hill St"],
            ["Pat Doe", "603-555-0100", "3 Hill Street"],    // listed twice
        ])
        let preview = ClientImport.preview(t, fields: [.name, .phone, .address], existing: [],
                                           addressesAsProperties: true)
        #expect(preview.new.count == 1 && preview.properties == 2 && preview.duplicates == 1)
        let owners = preview.outcomes.compactMap { if case let .property(_, _, id) = $0 { id } else { nil } }
        #expect(owners == ["row:0", "row:0"])
    }

    // A client PlowR has with no address isn't given a "property" that's
    // really their only address: it's the same client, skipped.
    @Test func noPropertyForAClientWithoutAnAddress() {
        let existing = [ClientImport.Known(id: "c1", name: "Pat Doe", phone: "6035550100", address: "")]
        let t = table(["Name", "Phone", "Address"], [["Pat Doe", "603-555-0100", "1 Main St"]])
        let preview = ClientImport.preview(t, fields: [.name, .phone, .address], existing: existing,
                                           addressesAsProperties: true)
        #expect(preview.duplicates == 1 && preview.properties == 0)
    }

    // Export-style headers: an Address column beside City, State and ZIP is
    // the street, and the address is put together from all of them.
    @Test func anAddressColumnBesideCityStateAndZipIsTheStreet() {
        let header = ["Name", "Address", "City", "State", "ZIP"]
        let fields = ClientImport.guess(header)
        #expect(fields == [.name, .street, .city, .state, .zip])
        let draft = ClientImport.draft(from: ["Pat Doe", "1 Main St", "Claremont", "NH", "03743"], fields: fields)
        #expect(draft.address == "1 Main St, Claremont, NH 03743")
        // Mapped by hand as a full address, the parts it lacks are still added,
        // and those it holds aren't repeated.
        let full = ClientImport.draft(from: ["Pat Doe", "1 Main St, Claremont", "Claremont", "NH", "03743"],
                                      fields: [.name, .address, .city, .state, .zip])
        #expect(full.address == "1 Main St, Claremont, NH 03743")
        let state = ClientImport.draft(from: ["Pat Doe", "1 Main St", "MA"], fields: [.name, .address, .state])
        #expect(state.address == "1 Main St, MA")       // "MA" isn't in "Main"
    }

    @Test func billingAloneIsStillTheAddress() {
        let fields = ClientImport.guess(["Name", "Billing Street 1", "Billing City", "Service Notes"])
        #expect(fields == [.name, .street, .city, .notes])
    }

    @Test func longerHeadersByTheirWords() {
        #expect(ClientImport.guess(["Account #", "Client Phone #", "Customer Email Address", "Mailing Address",
                                    "Zip/Postal", "Gate Notes"])
            == [.ignore, .phone, .email, .address, .zip, .notes])
        #expect(ClientImport.guess(["Address1", "Address2", "Phone2"]) == [.street, .street2, .phone])
        #expect(ClientImport.guess(["Estate Name"]) == [.ignore])      // "state" only as a word
    }

    // Google Contacts' export: "Labels" with " ::: " between them.
    @Test func googleLabelsAreTags() {
        let draft = ClientImport.draft(from: ["Pat Doe", "* myContacts ::: Commercial ::: Weekly"],
                                       fields: [.name, .tags])
        #expect(draft.tags == ["Commercial", "Weekly"])
    }

    @Test func aCompanyThatIsTheNameIsntANote() {
        let draft = ClientImport.draft(from: ["Doe Farms", "Doe Farms"], fields: [.name, .company])
        #expect(draft.notes.isEmpty)
    }

    // Thousands of rows against thousands of clients: indexed, not compared
    // pairwise (which took 25 s for 2,000 by 2,000).
    @Test func fiveThousandRowsTakeAMoment() {
        let rows = (0..<5_000).map { ["Client \($0)", String(format: "603-555-%04d", $0 % 10_000), "\($0) Main St"] }
        let existing = (0..<5_000).map {
            ClientImport.Known(id: "c\($0)", name: "Known \($0)", phone: String(format: "603-444-%04d", $0),
                               address: "\($0) Elm St")
        }
        let start = Date()
        let preview = ClientImport.preview(table(["Name", "Phone", "Address"], rows), fields: [.name, .phone, .address],
                                           existing: existing)
        #expect(preview.new.count == 5_000)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    // Google Contacts puts a "- Label" column before each "- Value": the
    // value is the field, not the label beside it.
    @Test func googleContactsColumns() {
        let header = ["First Name", "Middle Name", "Last Name", "Phonetic First Name", "Organization Name",
                      "Organization Title", "Notes", "Labels", "E-mail 1 - Label", "E-mail 1 - Value",
                      "Phone 1 - Label", "Phone 1 - Value", "Address 1 - Label", "Address 1 - Formatted",
                      "Address 1 - Street", "Address 1 - City", "Address 1 - PO Box", "Address 1 - Region",
                      "Address 1 - Postal Code", "Address 1 - Country", "Address 1 - Extended Address"]
        let fields = ClientImport.guess(header)
        #expect(fields == [.firstName, .ignore, .lastName, .ignore, .company, .ignore, .notes, .tags,
                           .ignore, .email, .ignore, .phone, .ignore, .address, .street, .city, .ignore, .state,
                           .zip, .ignore, .ignore])
        let row = ["Pat", "", "Doe", "", "", "", "", "* myContacts ::: Weekly", "* Home", "pat@example.com",
                   "Mobile", "(603) 555-0100", "Home", "1 Main St\nClaremont, NH 03743\nUS", "1 Main St",
                   "Claremont", "", "NH", "03743", "US", ""]
        let draft = ClientImport.draft(from: row, fields: fields)
        #expect(draft.name == "Pat Doe" && draft.phone == "(603) 555-0100" && draft.email == "pat@example.com")
        #expect(draft.address == "1 Main St, Claremont, NH 03743, US")
        #expect(draft.tags == ["Weekly"])
        #expect(ClientImport.addressKey(draft.address) == ClientImport.addressKey("1 Main Street, Claremont, NH 03743"))
    }

    @Test func aColumnAboutAFieldIsntTheField() {
        #expect(ClientImport.guess(["Phone Type", "Phone", "Email Opt In", "Email"]) == [.ignore, .phone, .ignore, .email])
    }

    // A full address beside City, State and ZIP columns isn't given them twice.
    @Test func aFullAddressBesideItsPartsIsntDoubled() {
        let billing = ["Name", "Billing Address", "Billing City", "Billing State", "Billing ZIP"]
        let fields = ClientImport.guess(billing)
        #expect(fields == [.name, .address, .city, .state, .zip])
        let row = ["Pat Doe", "1 Main St, Claremont, NH 03743", "Claremont", "NH", "03743"]
        #expect(ClientImport.draft(from: row, fields: fields).address == "1 Main St, Claremont, NH 03743")
        let full = ClientImport.guess(["Name", "Full Address", "City"])
        #expect(ClientImport.draft(from: ["Pat Doe", "1 Main St, Claremont, NH 03743", "Claremont"], fields: full).address
            == "1 Main St, Claremont, NH 03743")
        // A street named for the town still gets the town.
        let street = ClientImport.draft(from: ["Pat Doe", "12 Claremont Rd", "Claremont", "NH"],
                                        fields: [.name, .street, .city, .state])
        #expect(street.address == "12 Claremont Rd, Claremont, NH")
    }

    // Outlook lists Business, Home and Mobile columns: the filled one wins.
    @Test func theFilledColumnWinsAmongLikeOnes() {
        let header = ["Name", "Business Phone", "Home Phone", "Mobile Phone"]
        let rows = [["Pat Doe", "", "", "603-555-0100"], ["Sam Roe", "", "603-555-0200", "603-555-0201"]]
        #expect(ClientImport.guess(header, rows: rows) == [.name, .ignore, .ignore, .phone])
        #expect(ClientImport.guess(header) == [.name, .phone, .ignore, .ignore])     // no rows: the first
        // An address is never put together from two groups of columns.
        let places = ["Name", "Business Street", "Business City", "Home Street", "Home City"]
        let filled = [["A", "1 Biz St", "Worktown", "", ""], ["B", "2 Biz St", "", "2 Home St", "Hometown"],
                      ["C", "3 Biz St", "", "3 Home St", "Hometown"], ["D", "", "", "4 Home St", "Hometown"]]
        #expect(ClientImport.guess(places, rows: filled) == [.name, .street, .city, .ignore, .ignore])
    }

    @Test func wordsWithAnXArentAnExtension() {
        #expect(ClientImport.phoneKey("Text only: 603-555-0100") == "6035550100")
        #expect(ClientImport.phoneKey("Fax 603-555-0100") == "6035550100")
        #expect(ClientImport.phoneKey("Box 12, 603-555-0100") == "126035550100")
        #expect(ClientImport.phoneKey("603-555-0100 X 4") == "6035550100")
        #expect(ClientImport.phoneKey("603-555-0100 extension 12") == "6035550100")
        #expect(ClientImport.phoneKey("603-555-0100 x 12 (office)") == "6035550100")
    }

    // Renamed in the spreadsheet: the same phone at the same place is them.
    @Test func theSamePhoneAtTheSamePlaceIsADuplicateUnderAnyName() {
        let existing = [ClientImport.Known(id: "c1", name: "Pat Doe", phone: "6035550100", address: "1 Main St")]
        let t = table(["Name", "Phone", "Address"], [["Pat & Kim Doe", "603-555-0100", "1 Main Street"],
                                                     ["Kim Doe", "603-555-0100", "9 Lake Rd"]])
        let preview = ClientImport.preview(t, fields: [.name, .phone, .address], existing: existing)
        #expect(preview.duplicates == 1 && preview.new.map(\.name) == ["Kim Doe"] && preview.sharedPhones == 1)
    }

    // A blank row in the file still counts, so "row 5" is row 5.
    @Test func problemRowsAreTheSpreadsheetsRows() throws {
        let text = "Name,Phone\nPat Doe,1\n\n\"Sam\nRoe\",2\n,3\n"
        let t = try CSVReader.read(Data(text.utf8))
        #expect(t.rowNumbers == [2, 4, 5])
        let preview = ClientImport.preview(t, fields: [.name, .phone], existing: [])
        #expect(preview.problems.map(\.row) == [5])
        let hinted = try CSVReader.read(Data("sep=,\n\nName\nPat\n".utf8))
        #expect(hinted.rowNumbers == [3])         // Excel hides the sep= line
    }
}
