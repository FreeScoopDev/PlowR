import Foundation

/// A number typed into a text field: a price, a discount, a rate.
///
/// The decimal keypad types the region's decimal separator, which in much of
/// the world is a comma. `Double(_:)` reads only a dot, so "12,50" was
/// unreadable and silently became the default price, or a 0 discount.
///
/// In a region that writes decimals with a comma, one comma and no dot is a
/// decimal comma ("12,50" is 12.5). Elsewhere a comma is a thousands
/// separator, so "1,250" isn't read as 1.25: an iPad's keyboard, a hardware
/// keyboard or a paste can type one, and $1.25 recorded for $1,250 is worse
/// than a field that can't be read. Anything else with a comma, such as
/// "1,250.00" or "1,2,3", stays unreadable rather than guessed at. Not a real
/// amount ("nan", "inf", which `Double(_:)` accepts) is unreadable too.
///
/// `nonisolated` because it's plain parsing, used from views, models and
/// tests; the app target defaults everything to @MainActor.
nonisolated enum DecimalText {

    /// `value` with up to `places` decimals and no trailing zeros (8.875,
    /// 1234.5, 2); "0" for a value that isn't a number.
    static func trimmed(_ value: Double, places: Int = 4) -> String {
        guard value.isFinite else { return "0" }
        var text = String(format: "%.\(places)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// The number in `text`, or nil when there isn't one.
    static func number(_ text: String?, locale: Locale = .current) -> Double? {
        number(text, decimalComma: locale.decimalSeparator == ",")
    }

    /// The number in `text`, reading one comma and no dot as a decimal comma
    /// when `decimalComma` is set, whatever the region. For a figure that a
    /// comma can't be separating thousands of, such as a rate up to 100.
    static func number(_ text: String?, decimalComma: Bool) -> Double? {
        var text = (text ?? "").trimmingCharacters(in: .whitespaces)
        if decimalComma, !text.contains("."), text.filter({ $0 == "," }).count == 1 {
            text = text.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
