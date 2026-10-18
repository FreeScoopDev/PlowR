import Foundation

/// Money as PlowR writes it, on every screen, document and text (money
/// review, 2026-10-18).
///
/// It used to be written four ways: `"$%.2f"` on PDFs and some screens (no
/// thousands separator, "$12500.00"), the device region's currency style
/// elsewhere ("US$" or "1.234,56 $US" outside the US), and whole dollars on
/// the tiles and the Clients list, where $0.40 owed read "$0" in the owed
/// colour and $148.50 read "$148" (half to even, where the totals round half
/// away from zero). Now there is one currency, one locale and one rounding.
///
/// CSV export doesn't use this: a spreadsheet needs plain numbers
/// (`CSVExport.money`), and a price field holds plain text it can read back
/// (`StopRecording.money`).
///
/// `nonisolated`: called from PDF drawing, models and tests.
nonisolated enum Money {
    /// Prices are in US dollars (US launch).
    static let currencyCode = "USD"
    /// Written the US way wherever the phone's region is set: "$1,234.50".
    static let locale = Locale(identifier: "en_US")

    /// To the cent, with thousands separators: "$12,500.00", "-$5.25".
    /// Rounded to the cent the one way the totals are (`InvoiceLines.cents`),
    /// so a half cent shows as the totals count it.
    static func text(_ amount: Double) -> String {
        InvoiceLines.roundedToCent(amount).formatted(style(fraction: 2...2))
    }

    /// Whole dollars, for tiles and badges: "$12,500", "$149" for $148.50.
    /// An amount that isn't zero never shows as "$0": under half a dollar it
    /// shows to the cent ("$0.40"), so a small balance still reads as owed.
    static func whole(_ amount: Double) -> String {
        let cents = InvoiceLines.cents(amount)
        let dollars = (abs(cents) + 50) / 100
        if dollars == 0 && cents != 0 { return text(amount) }
        return Double(cents < 0 ? -dollars : dollars).formatted(style(fraction: 0...0))
    }

    /// A rate per square foot, which can go below a cent: "$0.015", "$0.10".
    static func rate(_ amount: Double) -> String {
        amount.formatted(style(fraction: 2...3))
    }

    /// A price multiplier as set: "1.25×", "1.5×", "2×".
    static func multiplier(_ factor: Double) -> String {
        factor.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "×"
    }

    private static func style(fraction: ClosedRange<Int>) -> FloatingPointFormatStyle<Double>.Currency {
        .currency(code: currencyCode).locale(locale).precision(.fractionLength(fraction))
    }
}
