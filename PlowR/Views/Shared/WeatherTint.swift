import SwiftUI

/// The kinds of weather the app colours, read from a condition's description,
/// with one colour for each kind as a background (the Dashboard's and the
/// route screen's weather strip) and as an icon (the Schedule's forecast).
/// The Dashboard and the route screen each had a copy of the background
/// colours, and the Schedule its own list of kinds: thunder was purple on one
/// screen and yellow on another, and only the Schedule knew "freezing".
enum WeatherKind {
    case snow, thunder, rain, fog, cloudy, clear, other

    init(_ description: String) {
        let d = description.lowercased()
        let has = { (words: [String]) in words.contains { d.contains($0) } }
        // In order: "Snow Showers" is snow, "Freezing Rain" is icy.
        self = has(["snow", "blizzard", "freezing"]) ? .snow
            : has(["thunder"]) ? .thunder
            : has(["rain", "shower", "drizzle"]) ? .rain
            : has(["fog"]) ? .fog
            : has(["cloud", "overcast"]) ? .cloudy
            : has(["clear", "sun"]) ? .clear
            : .other
    }

    /// Behind white text: a weather strip.
    var background: Color {
        switch self {
        case .snow: .blue
        case .thunder: .purple
        case .rain: .indigo
        case .fog: Color(white: 0.4)
        case .clear: .teal
        case .cloudy, .other: Color(.systemGray)
        }
    }

    /// An icon on the page's background: a forecast's symbol. A clear day's
    /// sun is orange rather than the strip's teal.
    var iconColor: Color {
        switch self {
        case .snow: .blue
        case .thunder: .purple
        case .rain: .indigo
        case .fog: .gray
        case .cloudy: Color(.systemGray)
        case .clear, .other: .orange
        }
    }
}
