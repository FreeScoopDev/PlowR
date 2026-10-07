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
            ["Pat Doe", "603-555-0100", "1 Main St"],          // already in PlowR, by phone
            ["Sam Roe", "", "2 Elm St"],                      // new
            ["", "603-555-0199", "3 Oak St"],                 // no name
            ["sam  roe", "", "2 elm st."],                    // the same as the row above
            ["Lee Poe", "(603) 555-0177", "4 Pine St"],       // new
        ])
        let existing = [ClientImport.Known(id: "c1", name: "Patricia Doe", phone: "6035550100", address: "")]
        let preview = ClientImport.preview(t, fields: [.name, .phone, .address], existing: existing)
        #expect(preview.new.map(\.name) == ["Sam Roe", "Lee Poe"])
        #expect(preview.duplicates == 2)
        #expect(preview.problems.map(\.row) == [4])           // spreadsheet row: the header is row 1
        #expect(preview.outcomes.first == .duplicate(ClientImport.draft(from: t.rows[0], fields: [.name, .phone, .address]),
                                                     of: "Patricia Doe"))
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
        #expect(ClientImport.preview(other, fields: [.name, .phone, .address], existing: [],
                                     addressesAsProperties: true).duplicates == 1)
    }
}
