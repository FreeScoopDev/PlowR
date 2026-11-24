import Foundation

/// A distance's unit, as a trip was typed in.
nonisolated enum DistanceUnit: String, CaseIterable {
    case miles = "mi"
    case kilometers = "km"

    /// Miles where the region measures roads in miles (the US and the UK),
    /// kilometres elsewhere.
    static func `default`(for locale: Locale) -> DistanceUnit {
        switch locale.measurementSystem {
        case .us, .uk: .miles
        default: .kilometers
        }
    }

    var length: UnitLength {
        switch self {
        case .miles: .miles
        case .kilometers: .kilometers
        }
    }
}

/// The mileage log's rules. Every distance is typed: PlowR measures none
/// (RouteOptimizer's distances are straight lines for ordering stops, and
/// LocationManager keeps no odometer), and shows no rate per mile.
enum Mileage {
    /// A typed distance, or nil when it can't be saved: unreadable, zero or
    /// less, or beyond any day's driving. Kept to two places, as the editor
    /// and the Mileage file show it, so reopening a saved trip reads back
    /// what was stored and isn't counted as a change.
    static func distance(typed text: String, locale: Locale = .current) -> Double? {
        guard let value = DecimalText.number(text, locale: locale) else { return nil }
        let rounded = (value * 100).rounded() / 100
        guard rounded > 0, rounded < 100_000 else { return nil }
        return rounded
    }

    /// The entries' distances added up in `unit`, each converted from the
    /// unit it was typed in.
    static func total(_ entries: [MileageEntry], in unit: DistanceUnit) -> Double {
        entries.reduce(0) { sum, entry in
            sum + Measurement(value: entry.distance, unit: entry.unit.length).converted(to: unit.length).value
        }
    }

    /// "12.5 mi": in the unit given, never converted to the region's own.
    static func text(_ distance: Double, unit: DistanceUnit, locale: Locale = .current) -> String {
        Measurement(value: distance, unit: unit.length)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale))
    }

    /// The delete question, naming the trip and its distance.
    static func deleteTitle(for entry: MileageEntry) -> String {
        let purpose = entry.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let distance = text(entry.distance, unit: entry.unit)
        return purpose.isEmpty ? "Delete this \(distance) trip?" : "Delete \u{201C}\(purpose)\u{201D}, \(distance)?"
    }
}
