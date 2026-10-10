import CoreLocation
import Foundation
import WeatherKit

/// Coordinates rounded to two decimals (about 1 km) before they leave the
/// phone: the Dashboard's weather and the Service Report's both send these.
nonisolated enum RoundedCoordinates {
    static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

/// The estimated weather on a past day at a property, for the Service
/// Report: the day's snowfall, precipitation, low and high, from Apple
/// WeatherKit's daily history. These are a weather model's estimates for
/// the area, whole-day totals (before and after the visit), not
/// measurements at the property, and the report says so on every line.
///
/// Only days the history surely covers are asked for: from 2022 on (WeatherKit
/// keeps about five years), and up to yesterday (today's figures are partly
/// forecast). Days are the phone's, as every
/// other time in the report is.
enum VisitWeather {
    struct Day: Equatable {
        /// Inches.
        let snowfall: Double
        let precipitation: Double
        /// °F.
        let low: Double
        let high: Double
    }

    /// What the report has for weather.
    enum Lookup: Equatable {
        /// The place has no pin: no weather lines.
        case notLookedUp
        /// The lookup failed (no signal, the service down): said once.
        case failed
        /// Each day's estimate, by "yyyy-MM-dd".
        case days([String: Day])
    }

    /// The archive's first day.
    static let firstDay = DateComponents(year: 2022, month: 1, day: 1)

    /// The days worth asking for, given the visits' days: from the archive's
    /// first day to yesterday. Nil when there are none.
    static func span(of visitDays: [Date], now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let first = visitDays.min(), let last = visitDays.max(),
              let archiveStart = calendar.date(from: firstDay),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return nil }
        let start = max(calendar.startOfDay(for: first), archiveStart)
        let end = min(calendar.startOfDay(for: last), yesterday)
        return start <= end ? start...end : nil
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// One day's figures in inches (snow depth, not its water) and °F.
    struct Figures {
        var date: Date
        var snowfallInches: Double
        var precipitationInches: Double
        var lowF: Double
        var highF: Double
    }

    /// A day's figures from WeatherKit's measurements.
    static func figures(date: Date, snowfall: Measurement<UnitLength>, precipitation: Measurement<UnitLength>,
                        low: Measurement<UnitTemperature>, high: Measurement<UnitTemperature>) -> Figures {
        Figures(date: date,
                snowfallInches: snowfall.converted(to: .inches).value,
                precipitationInches: precipitation.converted(to: .inches).value,
                lowF: low.converted(to: .fahrenheit).value,
                highF: high.converted(to: .fahrenheit).value)
    }

    /// The daily history for a span at a place: WeatherKit's, or a test's.
    typealias History = (_ location: CLLocation, _ start: Date, _ end: Date) async throws -> [Figures]

    static let weatherKitHistory: History = { location, start, end in
        let history = try await WeatherKit.WeatherService.shared.weather(
            for: location, including: .daily(startDate: start, endDate: end))
        return history.forecast.map { day in
            figures(date: day.date, snowfall: day.precipitationAmountByType.snowfallAmount.amount,
                    precipitation: day.precipitationAmountByType.precipitation,
                    low: day.lowTemperature, high: day.highTemperature)
        }
    }

    /// The days by "yyyy-MM-dd" in the phone's calendar, as the report's
    /// visits are; days outside the span are left out.
    static func days(_ figures: [Figures], span: ClosedRange<Date>,
                     calendar: Calendar = .current) -> [String: Day] {
        var days: [String: Day] = [:]
        for figure in figures {
            let day = WeatherService.calendarDay(of: figure.date, calendar: calendar)
            guard span.contains(day) else { continue }
            days[dayString(day, calendar: calendar)] = Day(snowfall: figure.snowfallInches,
                                                           precipitation: figure.precipitationInches,
                                                           low: figure.lowF, high: figure.highF)
        }
        return days
    }

    /// The estimates for the visits' days at a place. Not looked up without
    /// a pin; failed (not empty) when it can't be had, so the report never
    /// reads a failed lookup as days with no figures.
    static func lookUp(latitude: Double, longitude: Double, visitDays: [Date], now: Date = .now,
                       history: History? = nil) async -> Lookup {
        guard AddressPin.exists(latitude: latitude, longitude: longitude) else { return .notLookedUp }
        guard let span = span(of: visitDays, now: now) else { return .days([:]) }
        // Never WeatherKit under tests; a test passes its own history.
        guard let history = history ?? (WeatherService.unavailable ? nil : weatherKitHistory),
              let end = Calendar.current.date(byAdding: .day, value: 1, to: span.upperBound),
              let figures = try? await history(WeatherService.location(latitude: latitude, longitude: longitude),
                                               span.lowerBound, end) else { return .failed }
        return .days(days(figures, span: span))
    }

    /// An amount in inches as the report prints it: to the hundredth, and
    /// "a trace" for an amount above zero that rounds to nothing, so a
    /// line never says snow fell with no precipitation.
    static func inches(_ value: Double) -> String {
        if value > 0, value < 0.005 { return "a trace" }
        return "\(value.formatted(.number.precision(.fractionLength(2)))) in"
    }

    /// The report's line for a day.
    static func line(_ day: Day?) -> String {
        guard let day else { return "Estimated weather that day: no estimate for this day" }
        return "Estimated weather that day (whole day, weather model): \(inches(day.snowfall)) of snow, "
            + "\(inches(day.precipitation)) of precipitation, low \(Int(day.low.rounded()))°F, high \(Int(day.high.rounded()))°F"
    }
}
