import Foundation
import Testing
@testable import PlowR

/// Import Clients' spreadsheet reader: files as Excel, Numbers, Google Sheets
/// and other apps really write them.
struct CSVReaderTests {
    private func table(_ text: String, encoding: String.Encoding = .utf8, bom: [UInt8] = []) throws -> CSVReader.Table {
        try CSVReader.read(Data(bom) + (text.data(using: encoding) ?? Data()))
    }

    @Test func aPlainFile() throws {
        let t = try table("Name,Phone,Address\nPat Doe,603-555-0100,1 Main St\nSam Roe,603-555-0101,2 Elm St\n")
        #expect(t.header == ["Name", "Phone", "Address"])
        #expect(t.rows == [["Pat Doe", "603-555-0100", "1 Main St"], ["Sam Roe", "603-555-0101", "2 Elm St"]])
    }

    @Test func quotesHoldCommasLineBreaksAndQuotes() throws {
        let csv = "Name,Address,Notes\r\n\"Doe, Pat\",\"1 Main St, Apt 2\",\"Gate code 1234\nDog: \"\"Rex\"\"\"\r\n"
        let t = try table(csv)
        #expect(t.rows == [["Doe, Pat", "1 Main St, Apt 2", "Gate code 1234\nDog: \"Rex\""]])
    }

    @Test func spacesAroundFieldsAreTrimmedButNotInsideQuotes() throws {
        let t = try table("Name , Phone\n  Pat Doe ,  \"  603 \"  \n")
        #expect(t.header == ["Name", "Phone"])
        #expect(t.rows == [["Pat Doe", "  603 "]])
    }

    @Test func semicolonsAndTabsAreFound() throws {
        #expect(try table("Name;Phone\nPat;603\n").rows == [["Pat", "603"]])
        #expect(try table("Name\tPhone\nPat\t603\n").rows == [["Pat", "603"]])
        // A comma inside quotes in the header doesn't count.
        #expect(CSVReader.separator(of: "\"Last, First\";Phone\n") == ";")
        #expect(CSVReader.separator(of: "Name\n") == ",")
    }

    @Test func everyLineEndingAndBlankRows() throws {
        let t = try table("Name,Phone\r\rPat,1\rSam,2\n\n,\nLee,3")
        #expect(t.rows == [["Pat", "1"], ["Sam", "2"], ["Lee", "3"]])
    }

    @Test func shortRowsArePaddedAndWideOnesKept() throws {
        let t = try table("Name,Phone,Email\nPat\nSam,2,s@x.com,extra\n")
        #expect(t.rows == [["Pat", "", ""], ["Sam", "2", "s@x.com", "extra"]])
    }

    @Test func encodingsExcelAndOthersWrite() throws {
        let csv = "Name,City\nRené Côté,Montréal\n"
        let expected = [["René Côté", "Montréal"]]
        #expect(try table(csv).rows == expected)                                               // UTF-8
        #expect(try table(csv, bom: [0xEF, 0xBB, 0xBF]).header == ["Name", "City"])           // UTF-8 with a BOM
        #expect(try table(csv, encoding: .utf16LittleEndian, bom: [0xFF, 0xFE]).rows == expected)
        #expect(try table(csv, encoding: .utf16BigEndian, bom: [0xFE, 0xFF]).rows == expected)
        #expect(try table(csv, encoding: .windowsCP1252).rows == expected)                    // Excel on Windows
    }

    @Test func aSpreadsheetFileIsntText() {
        #expect(throws: CSVReader.Problem.notText) { try CSVReader.read(Data([0x50, 0x4B, 0x03, 0x04, 1, 2])) }
        #expect(throws: CSVReader.Problem.empty) { try CSVReader.read(Data("\n\n,,\n".utf8)) }
    }

    // CSVExport puts an apostrophe before text that looks like a formula; a
    // spreadsheet may too. It isn't the client's.
    @Test func theFormulaGuardIsTakenOff() throws {
        let t = try table("Name,Notes\nPat,'=SUM(A1)\nSam,'-not a number\nLee,'Tis the season\n")
        #expect(t.rows.map { $0[1] } == ["=SUM(A1)", "-not a number", "'Tis the season"])
    }

    // PlowR's own export reads back as it went out.
    @Test func plowRsOwnExportReadsBack() throws {
        let exported = CSVExport.document(header: ["Name", "Notes"],
                                          rows: [[.text("Doe, Pat"), .text("=gate \"A\"\nback lot")]])
        let t = try CSVReader.read(Data(exported.utf8))
        #expect(t.header == ["Name", "Notes"])
        #expect(t.rows == [["Doe, Pat", "=gate \"A\"\nback lot"]])
    }
}
