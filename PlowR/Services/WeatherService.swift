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

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let wind_direction_10m: Double
    }
    let current: Current
}

actor WeatherService {
    static let shared = WeatherService()
    private init() {}

    func fetch(latitude: Double, longitude: Double) async throws -> WeatherCondition {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m&temperature_unit=fahrenheit&wind_speed_unit=mph&forecast_days=1"
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
}
