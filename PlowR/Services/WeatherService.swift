import CoreLocation
import Foundation
import WeatherKit

struct WeatherCondition {
    let temperatureF: Double
    let description: String
    let symbolName: String
    let windSpeedMph: Double
    let windDirectionDegrees: Double

    var windDirectionLabel: String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((windDirectionDegrees + 22.5) / 45.0) % 8
        return dirs[idx]
    }
}

struct DayForecast {
    let date: Date
    let maxTempF: Double
    let minTempF: Double
    let weatherCode: Int
    let precipitationMm: Double
    /// The weather model's snowfall for the whole day, in inches; nil when
    /// it gave none (StormWatch).
    var snowfallInches: Double?

    var symbolName: String { wmoInfo(weatherCode).1 }
    var description: String { wmoInfo(weatherCode).0 }
    var hasSignificantPrecip: Bool { precipitationMm >= 2.54 } // ≥ 0.1 in
}

// MARK: - WMO weather code lookup (file-scope so DayForecast can use it)

nonisolated private func wmoInfo(_ code: Int) -> (String, String) {
    switch code {
    case 0:          return ("Clear", "sun.max.fill")
    case 1:          return ("Mostly Clear", "sun.min.fill")
    case 2:          return ("Partly Cloudy", "cloud.sun.fill")
    case 3:          return ("Overcast", "cloud.fill")
    case 45, 48:     return ("Fog", "cloud.fog.fill")
    case 51, 53, 55: return ("Drizzle", "cloud.drizzle.fill")
    case 61, 63, 65: return ("Rain", "cloud.rain.fill")
    case 66, 67:     return ("Freezing Rain", "cloud.sleet.fill")
    case 71, 73, 75: return ("Snow", "cloud.snow.fill")
    case 77:         return ("Snow Grains", "snowflake")
    case 80, 81, 82: return ("Showers", "cloud.heavyrain.fill")
    case 85, 86:     return ("Snow Showers", "cloud.snow.fill")
    case 95, 96, 99: return ("Thunderstorm", "cloud.bolt.rain.fill")
    // WeatherKit's conditions with no WMO code of their own (weatherCode(for:)).
    case 1001:       return ("Windy", "wind")
    case 1002:       return ("Hot", "sun.max.fill")
    case 1003:       return ("Frigid", "thermometer.low")
    case 1004:       return ("Haze", "sun.haze.fill")
    case 1005:       return ("Smoky", "smoke.fill")
    default:         return ("Conditions Vary", "cloud.fill")
    }
}

// MARK: - WeatherKit's conditions as weather codes

/// WeatherKit's condition as the WMO-style code PlowR's screens and alerts
/// already use (wmoInfo, NotificationService's adverse days), so switching
/// the source changed nothing downstream.
nonisolated func weatherCode(for condition: WeatherKit.WeatherCondition) -> Int {
    switch condition {
    case .clear: return 0
    case .hot: return 1002
    case .mostlyClear: return 1
    case .partlyCloudy: return 2
    case .mostlyCloudy, .cloudy: return 3
    case .breezy, .windy: return 1001
    case .frigid: return 1003
    case .foggy: return 45
    case .haze, .blowingDust: return 1004
    case .smoky: return 1005
    case .drizzle: return 53
    case .rain, .sunShowers: return 63
    case .heavyRain: return 65
    case .freezingDrizzle, .freezingRain: return 66
    // Freezing drizzle and sleet leave ice: alert-worthy, as freezing rain.
    case .sleet, .wintryMix: return 67
    case .flurries, .sunFlurries: return 71
    case .snow: return 73
    // Blowing snow drifts over what was cleared: as heavy snow, for alerts.
    case .heavySnow, .blizzard, .blowingSnow: return 75
    case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms,
         .tropicalStorm, .hurricane, .hail: return 95
    @unknown default: return -1
    }
}

// MARK: - Service

/// Weather from Apple's WeatherKit (Joe, 2026-10-10: Open-Meteo's free API
/// is for non-commercial apps only, and PlowR Pro is a subscription). The
/// location sent is rounded to about 1 km. Wherever weather shows, Apple's
/// attribution must too (WeatherAttribution).
actor WeatherService {
    static let shared = WeatherService()
    private init() {}

    /// Never under tests: there's no WeatherKit entitlement or network there.
    nonisolated static var unavailable: Bool { PlowRApp.isRunningUnderTests }

    nonisolated static func location(latitude: Double, longitude: Double) -> CLLocation {
        CLLocation(latitude: RoundedCoordinates.round(latitude), longitude: RoundedCoordinates.round(longitude))
    }

    func fetch(latitude: Double, longitude: Double) async throws -> WeatherCondition {
        guard !Self.unavailable else { throw URLError(.notConnectedToInternet) }
        let current = try await WeatherKit.WeatherService.shared.weather(
            for: Self.location(latitude: latitude, longitude: longitude), including: .current)
        return Self.condition(temperature: current.temperature, windSpeed: current.wind.speed,
                              windDirection: current.wind.direction, condition: current.condition)
    }

    func fetchForecast(latitude: Double, longitude: Double) async throws -> [DayForecast] {
        guard !Self.unavailable else { throw URLError(.notConnectedToInternet) }
        let daily = try await WeatherKit.WeatherService.shared.weather(
            for: Self.location(latitude: latitude, longitude: longitude), including: .daily)
        return daily.forecast.prefix(7).map { day in
            Self.day(date: day.date, high: day.highTemperature, low: day.lowTemperature, condition: day.condition,
                     precipitation: day.precipitationAmountByType.precipitation,
                     snowfall: day.precipitationAmountByType.snowfallAmount.amount)
        }
    }

    /// Current conditions in °F, mph and degrees, from WeatherKit's measurements.
    nonisolated static func condition(temperature: Measurement<UnitTemperature>, windSpeed: Measurement<UnitSpeed>,
                                      windDirection: Measurement<UnitAngle>,
                                      condition: WeatherKit.WeatherCondition) -> WeatherCondition {
        let (description, symbol) = wmoInfo(weatherCode(for: condition))
        return WeatherCondition(temperatureF: temperature.converted(to: .fahrenheit).value,
                                description: description, symbolName: symbol,
                                windSpeedMph: windSpeed.converted(to: .milesPerHour).value,
                                windDirectionDegrees: windDirection.converted(to: .degrees).value)
    }

    /// A forecast day in °F, millimetres and inches of snow (depth, not its
    /// water), from WeatherKit's measurements, as StormWatch's triggers are.
    nonisolated static func day(date: Date, high: Measurement<UnitTemperature>, low: Measurement<UnitTemperature>,
                                condition: WeatherKit.WeatherCondition, precipitation: Measurement<UnitLength>,
                                snowfall: Measurement<UnitLength>, calendar: Calendar = .current) -> DayForecast {
        DayForecast(date: Self.calendarDay(of: date, calendar: calendar),
                    maxTempF: high.converted(to: .fahrenheit).value,
                    minTempF: low.converted(to: .fahrenheit).value,
                    weatherCode: weatherCode(for: condition),
                    precipitationMm: precipitation.converted(to: .millimeters).value,
                    snowfallInches: snowfall.converted(to: .inches).value)
    }

    /// The phone's day for a WeatherKit day, which starts at midnight where
    /// the place is: counted from its middle, so a phone in a zone to the
    /// west doesn't put it on the day before.
    nonisolated static func calendarDay(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(12 * 3_600))
    }
}
