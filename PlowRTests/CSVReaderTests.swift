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

    // For an import, stray spaces are never wanted: trimmed, inside quotes too.
    @Test func spacesAroundFieldsAreTrimmed() throws {
        let t = try table("Name , Phone\n  Pat Doe ,  \"  603 \"  \n")
        #expect(t.header == ["Name", "Phone"])
        #expect(t.rows == [["Pat Doe", "603"]])
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

    // MARK: - Edge cases, as real files have them

    @Test func blankLinesBeforeTheHeaderDontHideItsSeparator() throws {
        #expect(try table("\nName;Phone\nPat;603\n").rows == [["Pat", "603"]])
        #expect(try table("  \r\nName\tPhone\nPat\t603\n").rows == [["Pat", "603"]])
    }

    @Test func excelsSeparatorHintLine() throws {
        let t = try table("sep=;\r\nName;Notes\r\nPat;a, b\r\n")
        #expect(t.header == ["Name", "Notes"])
        #expect(t.rows == [["Pat", "a, b"]])
        #expect(try table("sep=\t\nName\tPhone\nPat\t1\n").rows == [["Pat", "1"]])
    }

    @Test func textAfterAClosingQuoteKeepsItsSpaces() throws {
        #expect(try table("Name,Co\nPat,\"Smith\" Lawn Co\n").rows == [["Pat", "Smith Lawn Co"]])
        #expect(try table("Name,Co\nPat,\"Smith\"   ,x\n").rows == [["Pat", "Smith", "x"]])
    }

    @Test func aQuoteInsideAFieldIsJustACharacter() throws {
        #expect(try table("Name,Height\nO\"Brien,5'6\"\n").rows == [["O\"Brien", "5'6\""]])
    }

    @Test func emptyQuotedAndTrailingColumns() throws {
        #expect(try table("A,B,C\nx,\"\",z\n").rows == [["x", "", "z"]])
        #expect(try table("A,B\nx,\n").rows == [["x", ""]])
        #expect(try table("Name,Phone\n").rows.isEmpty)
    }

    @Test func everyFormulaGuardComesOff() throws {
        let t = try table("Name,Phone,Handle\nPat,'+1 603 555 0100,'@pat\n")
        #expect(t.rows == [["Pat", "+1 603 555 0100", "@pat"]])
    }

    // An older Mac encoding's accents may come out wrong, but a text file
    // always reads, never "not text".
    @Test func anyTextFileReads() throws {
        let bytes = Data("Name\nFran".utf8) + Data([0x8D]) + Data("ois\n".utf8)
        #expect(try CSVReader.read(bytes).rows.count == 1)
        // An old .xls: binary, full of NULs.
        #expect(throws: CSVReader.Problem.notText) { try CSVReader.read(Data([0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0x41])) }
    }

    @Test func onlyCRAndLFEndALine() throws {
        #expect(try table("Name,Notes\nPat,a\u{0B}b\u{2028}c\n").rows == [["Pat", "a\u{0B}b\u{2028}c"]])
    }

    @Test func anUnclosedQuoteIsReportedWithItsLine() throws {
        let t = try table("Name,Notes\nPat,\"open note\nSam,2\nLee,3\n")
        #expect(t.unclosedQuoteLine == 2)
        #expect(t.rows.count == 1)
        #expect(try table("Name,Notes\nPat,\"a\nb\"\nSam,2\n").unclosedQuoteLine == nil)
    }

    @Test func tiesGoCommaThenSemicolonThenTab() {
        #expect(CSVReader.separator(of: "a;b\tc\n") == ";")
        #expect(CSVReader.separator(of: "a,b;c\n") == ",")
    }

    // Characters only Windows Latin-1 has (’ is 0x92, € 0x80): pins that
    // encoding, which ISO Latin-1 would read as invisible control characters.
    @Test func windowsOnlyCharactersReadBack() throws {
        let t = try table("Name,Owed\nO\u{2019}Brien,\u{20AC}5\n", encoding: .windowsCP1252)
        #expect(t.rows == [["O\u{2019}Brien", "\u{20AC}5"]])
        // One undefined byte doesn't spoil the rest of the file.
        let stray = (try #require("Name\nO\u{2019}Brien".data(using: .windowsCP1252))) + Data([0x81, 0x0A])
        #expect(try CSVReader.read(stray).rows == [["O\u{2019}Brien\u{FFFD}"]])
    }

    @Test func aByteOrderMarkBeforeOtherBytesStillReads() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("Name\nRen".utf8) + Data([0xE9, 0x0A])
        #expect(try CSVReader.read(data).rows == [["René"]])
    }

    // Line numbers are the file's: the sep= line counts, and so do line
    // breaks inside quoted fields before the unclosed one.
    @Test func anUnclosedQuotesLineCountsEveryLine() throws {
        #expect(try table("sep=;\r\n\r\nName;Notes\r\nPat;\"open\n").unclosedQuoteLine == 4)
        #expect(try table("Name,Notes\nPat,\"a\nb\"\nSam,\"open\n").unclosedQuoteLine == 4)
    }

    @Test func aLineOfOnlySeparatorsOrQuotesIsntTheHeader() throws {
        #expect(try table("\t\nName,Phone\nPat,1\n").rows == [["Pat", "1"]])
        #expect(try table(",,,\nName;Phone\nPat;1\n").rows == [["Pat", "1"]])
        #expect(try table("\"\"\nName;Phone\nPat;1\n").rows == [["Pat", "1"]])
    }
}
