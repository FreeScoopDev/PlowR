import Testing
@testable import PlowR

/// Half a cent rounds up (away from zero), even when a Double holds it as
/// just under half. `InvoiceLines.cents` is the one rounding rule, so these
/// cover every total, tax, payment and export that goes through it.
struct MoneyRoundingTests {
    @Test func aHalfCentRoundsUp() {
        #expect(InvoiceLines.cents(1.005) == 101)      // 100.4999… as a Double
        #expect(InvoiceLines.cents(0.125) == 13)
        #expect(InvoiceLines.roundedToCent(2.675) == 2.68)
    }

    @Test func aHalfCentOwedBackRoundsAwayFromZeroToo() {
        #expect(InvoiceLines.cents(-1.005) == -101)
    }

    @Test func belowHalfStillRoundsDown() {
        #expect(InvoiceLines.cents(1.004) == 100)
        #expect(InvoiceLines.cents(1.00499) == 100)
        #expect(InvoiceLines.cents(19.99) == 1999)
    }

    /// The review's case: 5% on $2.90 is 14.5 cents, billed as 14.
    @Test func taxOnAnInvoiceRoundsAHalfCentUp() {
        let totals = Proposal.totals(subtotal: 2.90, discount: 0, taxRate: 5)
        #expect(totals.tax == 0.15)
        #expect(totals.total == 3.05)
    }

    /// Every amount from 1 cent to $200 at the rates PlowR's users are likely
    /// to have, against exact arithmetic in whole numbers.
    @Test(arguments: [5_000, 6_000, 6_250, 7_000, 7_250, 7_500, 8_000, 8_250, 8_875, 9_500, 10_250, 4_712])
    func taxMatchesExactArithmetic(rateInThousandthsOfAPercent rate: Int) {
        var wrong: [Int] = []
        for base in 1...20_000 {
            let exact = (2 * base * rate + 100_000) / 200_000   // half away from zero
            let tax = Proposal.totals(subtotal: Double(base) / 100, discount: 0,
                                      taxRate: Double(rate) / 1_000).tax
            if InvoiceLines.cents(tax) != exact { wrong.append(base) }
        }
        #expect(wrong.isEmpty, "first wrong bases (cents): \(wrong.prefix(5))")
    }

    @Test func aLineTotalRoundsAHalfCentUp() {
        // 3 × $1.115 = $3.345.
        #expect(InvoiceLines.roundedToCent(3 * 1.115) == 3.35)
    }

    @Test func largeAmountsKeepEveryCent() {
        #expect(InvoiceLines.cents(1_234_567.885) == 123_456_789)
        #expect(InvoiceLines.cents(999_999.99) == 99_999_999)
    }
}
