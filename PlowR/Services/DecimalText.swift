import Foundation

/// A number typed into a text field: a price, a discount, a rate.
///
/// The decimal keypad types the region's decimal separator, which in much of
/// the world is a comma. `Double(_:)` reads only a dot, so "12,50" was
/// unreadable and silently became the default price, or a 0 discount.
///
/// One comma and no dot is a decimal comma ("12,50" is 12.5). Anything else
/// with a comma, such as "1,250.00" or "1,2,3", stays unreadable rather than
/// guessed at. Not a real amount ("nan", "inf", which `Double(_:)` accepts)
/// is unreadable too.
///
/// `nonisolated` because it's plain parsing, used from views, models and
/// tests; the app target defaults everything to @MainActor.
nonisolated enum DecimalText {

    /// The number in `text`, or nil when there isn't one.
    static func number(_ text: String?) -> Double? {
        var text = (text ?? "").trimmingCharacters(in: .whitespaces)
        if !text.contains("."), text.filter({ $0 == "," }).count == 1 {
            text = text.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
