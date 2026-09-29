import Foundation

/// PlowR's own links (`plowr://`). Compiled into the app and the widget
/// extension, so what the widget opens and what the app handles can't drift
/// apart: Control Center's link was once a string in three places.
nonisolated enum PlowRLink: Equatable {
    /// The route in progress.
    case activeRoute
    /// Control Center's Complete Stop, with the stop the widget was showing:
    /// if the route has moved on since, that stop isn't the current one, and
    /// nothing is completed.
    case completeStop(UUID)

    static let scheme = "plowr"

    /// What Control Center's Complete Stop opens: the stop the widget shows,
    /// or with none (no route in progress, or every stop done), the route.
    static func completeStopControl(showing data: TodayRouteWidgetData?) -> PlowRLink {
        guard let data, data.isActive, let stopID = data.currentStopID else { return .activeRoute }
        return .completeStop(stopID)
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .activeRoute:
            components.host = "activeRoute"
        case .completeStop(let stopID):
            components.host = "completeStop"
            components.queryItems = [URLQueryItem(name: "stop", value: stopID.uuidString)]
        }
        return components.url
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "activeRoute":
            self = .activeRoute
        case "completeStop":
            let stop = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "stop" }?.value
            guard let stop, let stopID = UUID(uuidString: stop) else { return nil }
            self = .completeStop(stopID)
        default:
            return nil
        }
    }
}
