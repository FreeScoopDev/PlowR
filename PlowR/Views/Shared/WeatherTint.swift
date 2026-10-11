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

    /// An icon on the page's background: a forecast's symbol, the weather
    /// card's (1.7 tokens). Snow in the snow service's blue, rain in the
    /// scheduled blue, sun in amber, thunder in purple so a storm stands
    /// out, fog and cloud in grey.
    var iconColor: Color {
        switch self {
        case .snow: PlowRColor.Service.snow.fill
        case .rain: PlowRColor.Status.scheduled.fill
        case .clear, .other: PlowRColor.Status.owed.fill
        case .thunder: PlowRColor.Status.lead.fill
        // Grey text's colour, not the neutral status's quieter fill, which
        // is too faint for a glyph on its own (2:1).
        case .fog, .cloudy: PlowRColor.inkSecondary
        }
    }
}
