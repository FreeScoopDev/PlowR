import SwiftUI
import WeatherKit

/// Apple's attribution, which WeatherKit requires wherever its data shows:
/// the Apple Weather mark, and a link to the legal page naming its other
/// data sources. The mark is Apple's own image, fetched from WeatherKit, in
/// the light or dark version; until it arrives (or offline) the words stand
/// in, so the link is always there.
struct WeatherAttribution: View {
    /// For text where the mark can't be drawn (the Service Report PDF).
    nonisolated static let markText = "\u{F8FF} Weather"
    nonisolated static let legalPage = "https://weatherkit.apple.com/legal-attribution.html"

    /// Shown whenever any of WeatherKit's weather is: current conditions,
    /// or a forecast (the storm card, the Schedule's days), even when the
    /// other failed to load.
    nonisolated static func isNeeded(current: Bool, forecast: Bool) -> Bool { current || forecast }

    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherKit.WeatherAttribution?

    var body: some View {
        HStack(spacing: 6) {
            if let attribution {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL
                                                     : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(Self.markText)
                }
                .frame(height: 11)
                .accessibilityLabel("Apple Weather")
                Link("Data Sources", destination: attribution.legalPageURL)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            } else if let url = URL(string: Self.legalPage) {
                Text(Self.markText)
                Link("Data Sources", destination: url)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .task {
            guard !WeatherService.unavailable else { return }
            attribution = try? await WeatherKit.WeatherService.shared.attribution
        }
    }
}
