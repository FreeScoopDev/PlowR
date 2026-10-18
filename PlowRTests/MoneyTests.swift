import Foundation
import Testing
import UIKit
@testable import PlowR

/// Money is written one way everywhere (`Money`): to the cent with thousands
/// separators, whole dollars on tiles without ever hiding a small balance,
/// and rounded by the same rule as the totals.
struct MoneyTests {
    @Test func toTheCentWithThousands() {
        #expect(Money.text(12_500) == "$12,500.00")
        #expect(Money.text(1_234_567.8) == "$1,234,567.80")
        #expect(Money.text(0.4) == "$0.40")
        #expect(Money.text(0) == "$0.00")
    }

    /// A half cent shows the way the totals count it: half away from zero,
    /// even when a Double holds it as just under half. The currency style on
    /// its own rounds half to even ($0.125 would read "$0.12").
    @Test func halfCentsRoundLikeTheTotals() {
        for amount in [0.125, 1.005, 2.675, 148.505, -1.005, 0.015, 10.125] {
            let cents = InvoiceLines.cents(amount)
            let expected = (cents < 0 ? "-" : "") + "$" + String(format: "%d.%02d", abs(cents) / 100, abs(cents) % 100)
            #expect(Money.text(amount) == expected, "\(amount)")
        }
        #expect(Money.text(0.125) == "$0.13")
        #expect(Money.text(1.005) == "$1.01")
        #expect(Money.text(InvoiceLines.roundedToCent(2.675)) == Money.text(2.675))
    }

    @Test func owedBackShowsAMinus() {
        #expect(Money.text(-5.25) == "-$5.25")
        #expect(Money.whole(-1_200) == "-$1,200")
    }

    @Test func wholeDollarsForTiles() {
        #expect(Money.whole(12_500) == "$12,500")
        #expect(Money.whole(0) == "$0")
        #expect(Money.whole(148.49) == "$148")
    }

    /// $148.50 is $149, as the cent rule rounds: `%.0f` showed "$148".
    @Test func wholeDollarsRoundHalfAwayFromZero() {
        #expect(Money.whole(148.5) == "$149")
        #expect(Money.whole(2.5) == "$3")
        #expect(Money.whole(-2.5) == "-$3")
    }

    /// A balance under half a dollar isn't "$0" in the owed colour.
    @Test func aSmallBalanceNeverShowsAsZero() {
        #expect(Money.whole(0.4) == "$0.40")
        #expect(Money.whole(0.01) == "$0.01")
        #expect(Money.whole(0.49) == "$0.49")
        #expect(Money.whole(-0.4) == "-$0.40")
        #expect(Money.whole(0.5) == "$1")
        // Less than half a cent is nothing, to the cent as everywhere.
        #expect(Money.whole(0.004) == "$0")
    }

    @Test func aRatePerSquareFootKeepsItsFractionOfACent() {
        #expect(Money.rate(0.015) == "$0.015")
        #expect(Money.rate(0.1) == "$0.10")
        #expect(Money.rate(1_250) == "$1,250.00")
    }

    @Test func aDeductionHasAMinusSign() {
        #expect(Money.deducted(1_250) == "−$1,250.00")
        #expect(Money.deducted(-5.25) == "−$5.25")
    }

    /// The largest total a PDF prints fits its column on one line: with
    /// thousands separators, "$12,500.00" wrapped in the old one.
    @MainActor @Test func theLargestTotalFitsThePDFsColumn() throws {
        let contentW: CGFloat = 612 - 54 * 2
        let columns = PDFGenerator.totalsColumns(contentW: contentW)
        let bold = try #require(UIFont(name: "Verdana-Bold", size: 14))
        for amount in [12_500, 99_999.99, 999_999.99] {
            let width = NSAttributedString(string: Money.text(amount), attributes: [.font: bold]).size().width
            #expect(width < columns.valueW, "\(Money.text(amount)): \(width) in \(columns.valueW)")
        }
        let label = try #require(UIFont(name: "GillSans-SemiBold", size: 10))
        let paid = NSAttributedString(string: "PAID · BALANCE DUE", attributes: [.font: label, .kern: 1.5])
        #expect(paid.size().width < columns.labelW)
        #expect(columns.labelX + columns.labelW + columns.valueW <= contentW)
    }

    /// `%.2g` showed 1.25× as "1.2×".
    @Test func aMultiplierShowsAsSet() {
        #expect(Money.multiplier(1.25) == "1.25×")
        #expect(Money.multiplier(1.5) == "1.5×")
        #expect(Money.multiplier(1.75) == "1.75×")
        #expect(Money.multiplier(2) == "2×")
    }

    /// Nothing in the app writes money another way. CSV export and price
    /// fields write plain numbers on purpose (no "$"), so they don't match.
    @Test func noOtherMoneyFormatInTheApp() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PlowR")
        let banned = [#""$%"#, #""−$%"#, ".currency(code:", #""%.2g""#, #""$" + "#, #""$\("#, #""−" + Money"#]
        var found: [String] = []
        var scanned = 0
        let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" && file.lastPathComponent != "Money.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            scanned += 1
            for (number, line) in source.components(separatedBy: "\n").enumerated()
            where banned.contains(where: { line.contains($0) }) {
                found.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        // A path that went wrong would scan nothing and pass.
        #expect(scanned > 100, "scanned \(scanned) files in \(app.path)")
        #expect(found.isEmpty, "Use Money: \(found)")
    }
}
