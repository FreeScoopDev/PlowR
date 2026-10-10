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
    default:         return ("Conditions Vary", "cloud.fill")
    }
}

// MARK: - WeatherKit's conditions as weather codes

/// WeatherKit's condition as the WMO-style code PlowR's screens and alerts
/// already use (wmoInfo, NotificationService's adverse days), so switching
/// the source changed nothing downstream.
nonisolated func weatherCode(for condition: WeatherKit.WeatherCondition) -> Int {
    switch condition {
    case .clear, .hot: return 0
    case .mostlyClear: return 1
    case .partlyCloudy: return 2
    case .mostlyCloudy, .cloudy, .breezy, .windy, .frigid: return 3
    case .foggy, .haze, .smoky, .blowingDust: return 45
    case .drizzle: return 53
    case .rain, .sunShowers: return 63
    case .heavyRain: return 65
    case .freezingDrizzle, .freezingRain: return 66
    case .sleet, .wintryMix, .hail: return 67
    case .flurries, .sunFlurries: return 71
    case .snow: return 73
    case .heavySnow, .blizzard, .blowingSnow: return 75
    case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms,
         .tropicalStorm, .hurricane: return 95
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
    nonisolated static var unavailable: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    nonisolated static func location(latitude: Double, longitude: Double) -> CLLocation {
        CLLocation(latitude: RoundedCoordinates.round(latitude), longitude: RoundedCoordinates.round(longitude))
    }

    func fetch(latitude: Double, longitude: Double) async throws -> WeatherCondition {
        guard !Self.unavailable else { throw URLError(.notConnectedToInternet) }
        let current = try await WeatherKit.WeatherService.shared.weather(
            for: Self.location(latitude: latitude, longitude: longitude), including: .current)
        return Self.condition(temperatureF: current.temperature.converted(to: .fahrenheit).value,
                              windMph: current.wind.speed.converted(to: .milesPerHour).value,
                              windDegrees: current.wind.direction.converted(to: .degrees).value,
                              code: weatherCode(for: current.condition))
    }

    func fetchForecast(latitude: Double, longitude: Double) async throws -> [DayForecast] {
        guard !Self.unavailable else { throw URLError(.notConnectedToInternet) }
        let daily = try await WeatherKit.WeatherService.shared.weather(
            for: Self.location(latitude: latitude, longitude: longitude), including: .daily)
        return daily.forecast.prefix(7).map { day in
            Self.day(date: day.date,
                     highF: day.highTemperature.converted(to: .fahrenheit).value,
                     lowF: day.lowTemperature.converted(to: .fahrenheit).value,
                     code: weatherCode(for: day.condition),
                     precipitationMm: day.precipitationAmountByType.precipitation.converted(to: .millimeters).value,
                     snowfallInches: day.precipitationAmountByType.snowfallAmount.amount.converted(to: .inches).value)
        }
    }

    /// Current conditions, from values already in °F, mph and degrees.
    nonisolated static func condition(temperatureF: Double, windMph: Double, windDegrees: Double,
                                      code: Int) -> WeatherCondition {
        let (description, symbol) = wmoInfo(code)
        return WeatherCondition(temperatureF: temperatureF, description: description, symbolName: symbol,
                                windSpeedMph: windMph, windDirectionDegrees: windDegrees)
    }

    /// A forecast day, from values already in °F, millimetres and inches.
    nonisolated static func day(date: Date, highF: Double, lowF: Double, code: Int,
                                precipitationMm: Double, snowfallInches: Double) -> DayForecast {
        DayForecast(date: date, maxTempF: highF, minTempF: lowF, weatherCode: code,
                    precipitationMm: precipitationMm, snowfallInches: snowfallInches)
    }
}
