import Foundation

/// Coordinates rounded to two decimals (about 1 km) before they leave the
/// phone: the Dashboard's weather and the Service Report's both send these.
nonisolated enum RoundedCoordinates {
    static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

/// The estimated weather on a past day at a property, for the Service
/// Report: the day's snowfall, precipitation, low and high, from Open-Meteo's
/// historical forecast archive. These are a weather model's estimates for
/// the area, whole-day totals (before and after the visit), not
/// measurements at the property, and the report says so on every line.
///
/// Only days the archive really covers are asked for: from 2022 on, and up
/// to yesterday. (Before 2022 it answers with zeros rather than refusing,
/// and today's figures are partly forecast.) Days are the phone's, as every
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

    /// Open-Meteo's daily history for a span at a place, in inches and °F,
    /// in the phone's time zone.
    static func url(latitude: Double, longitude: Double, span: ClosedRange<Date>,
                    calendar: Calendar = .current) -> URL? {
        var components = URLComponents(string: "https://historical-forecast-api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(RoundedCoordinates.round(latitude))"),
            URLQueryItem(name: "longitude", value: "\(RoundedCoordinates.round(longitude))"),
            URLQueryItem(name: "start_date", value: dayString(span.lowerBound, calendar: calendar)),
            URLQueryItem(name: "end_date", value: dayString(span.upperBound, calendar: calendar)),
            URLQueryItem(name: "daily", value: "snowfall_sum,precipitation_sum,temperature_2m_min,temperature_2m_max"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: calendar.timeZone.identifier),
        ]
        return components?.url
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let snowfall_sum: [Double?]
            let precipitation_sum: [Double?]
            let temperature_2m_min: [Double?]
            let temperature_2m_max: [Double?]
        }
        let daily: Daily
    }

    /// The days in an Open-Meteo reply, by "yyyy-MM-dd". A day missing any
    /// figure is left out: the report says it has none, rather than a zero.
    static func parse(_ data: Data) throws -> [String: Day] {
        let daily = try JSONDecoder().decode(Response.self, from: data).daily
        var days: [String: Day] = [:]
        for (index, day) in daily.time.enumerated() {
            guard index < daily.snowfall_sum.count, index < daily.precipitation_sum.count,
                  index < daily.temperature_2m_min.count, index < daily.temperature_2m_max.count,
                  let snow = daily.snowfall_sum[index], let rain = daily.precipitation_sum[index],
                  let low = daily.temperature_2m_min[index], let high = daily.temperature_2m_max[index] else { continue }
            days[day] = Day(snowfall: snow, precipitation: rain, low: low, high: high)
        }
        return days
    }

    /// The estimates for the visits' days at a place. Not looked up without
    /// a pin; failed (not empty) when it can't be had, so the report never
    /// reads a failed lookup as days with no figures.
    static func lookUp(latitude: Double, longitude: Double, visitDays: [Date], now: Date = .now,
                       session: URLSession = .shared) async -> Lookup {
        guard AddressPin.exists(latitude: latitude, longitude: longitude) else { return .notLookedUp }
        guard let span = span(of: visitDays, now: now) else { return .days([:]) }
        guard let url = url(latitude: latitude, longitude: longitude, span: span) else { return .failed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let days = try? parse(data) else { return .failed }
        return .days(days)
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
