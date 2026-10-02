import Foundation

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

// MARK: - Private decoders

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let wind_direction_10m: Double
    }
    let current: Current
}

private struct ForecastResponse: Decodable {
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_sum: [Double]
        /// Centimetres. Optional: a missing value mustn't lose the forecast.
        let snowfall_sum: [Double?]?
    }
    let daily: Daily
}

// MARK: - WMO weather code lookup (file-scope so DayForecast can use it)

private func wmoInfo(_ code: Int) -> (String, String) {
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

// MARK: - Service

actor WeatherService {
    static let shared = WeatherService()
    private init() {}

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    func fetch(latitude: Double, longitude: Double) async throws -> WeatherCondition {
        // Rounded (~1.1 km): enough for weather, and less of the location sent to Open-Meteo.
        let lat = RoundedCoordinates.round(latitude)
        let lon = RoundedCoordinates.round(longitude)
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m&temperature_unit=fahrenheit&wind_speed_unit=mph&forecast_days=1"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let c = resp.current
        let (desc, sym) = wmoInfo(c.weather_code)
        return WeatherCondition(
            temperatureF: c.temperature_2m,
            description: desc,
            symbolName: sym,
            windSpeedMph: c.wind_speed_10m,
            windDirectionDegrees: c.wind_direction_10m
        )
    }

    func fetchForecast(latitude: Double, longitude: Double) async throws -> [DayForecast] {
        let lat = RoundedCoordinates.round(latitude)
        let lon = RoundedCoordinates.round(longitude)
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum&temperature_unit=fahrenheit&forecast_days=7&timezone=auto"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try Self.forecast(from: data)
    }

    /// Open-Meteo's daily forecast, as days. Snowfall comes in centimetres.
    static func forecast(from data: Data) throws -> [DayForecast] {
        let resp = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let d = resp.daily
        return d.time.indices.compactMap { i -> DayForecast? in
            guard i < d.weather_code.count,
                  i < d.temperature_2m_max.count,
                  i < d.temperature_2m_min.count,
                  i < d.precipitation_sum.count,
                  let date = dateParser.date(from: d.time[i]) else { return nil }
            return DayForecast(
                date: date,
                maxTempF: d.temperature_2m_max[i],
                minTempF: d.temperature_2m_min[i],
                weatherCode: d.weather_code[i],
                precipitationMm: d.precipitation_sum[i],
                snowfallInches: d.snowfall_sum.flatMap { i < $0.count ? $0[i] : nil }.map { $0 / 2.54 }
            )
        }
    }
}
